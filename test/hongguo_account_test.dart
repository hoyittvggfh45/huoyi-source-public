import 'package:duanju_app/core_bridge.dart';
import 'package:duanju_app/hongguo_account.dart';
import 'package:duanju_app/hongguo_related.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

class _SendSmsRepository extends FixtureRepository {
  _SendSmsRepository(this._error);

  final String _error;

  @override
  Future<Map<String, dynamic>> hongguoAccountSendSms(String mobile) async =>
      throw AppFailure(_error);
}

Drama hongguoDrama(String id, String title) => Drama(
  id: id,
  source: SourceSite.hongguo.id,
  title: title,
);

void main() {
  test('phone format accepts mainland 11 digits', () {
    expect(formatHongguoPhone('86', '13800138000'), '13800138000');
    expect(formatHongguoPhone('86', '138-0013-8000'), '13800138000');
    expect(parseHongguoPhone('13800138000'), '13800138000');
    expect(parseHongguoPhone('+886 0912345678'), '+886 912345678');
    expect(() => formatHongguoPhone('86', '23800138000'), throwsA(isA<HongguoLoginFailure>()));
    expect(() => formatHongguoPhone('86', '1380013800'), throwsA(isA<HongguoLoginFailure>()));
    expect(() => parseHongguoPhone('+8860912345678'), throwsA(isA<HongguoLoginFailure>()));
  });

  test('sms countdown ticks down to resend', () {
    final countdown = HongguoSmsCountdown(retrySeconds: 2);
    expect(countdown.canResend, isFalse);
    countdown.tick();
    expect(countdown.remainingSeconds, 1);
    countdown.tick();
    expect(countdown.canResend, isTrue);
  });

  test('qr countdown expires', () {
    final countdown = HongguoQrCountdown(expiresInSeconds: 1);
    expect(countdown.expired, isFalse);
    countdown.tick();
    expect(countdown.expired, isTrue);
  });

  test('credentials never print the cookie', () {
    const credentials = HongguoAccountCredentials(cookie: 'sessionid=abc123');
    expect(credentials.toString(), isNot(contains('abc123')));
    expect(credentials.toString(), contains('[redacted]'));
  });

  test('resume prefers cloud only when asked or newer', () {
    const local = HongguoLocalProgress(
      seriesId: '100',
      episodeId: 'e1',
      episodeIndex: 0,
      position: 10,
      duration: 100,
      updatedAt: 1000,
    );
    const cloud = HongguoCloudProgress(
      seriesId: '100',
      episodeId: 'e2',
      episodeIndex: 1,
      position: 20,
      duration: 100,
      updatedAt: 900,
    );
    const episodeIds = ['e1', 'e2'];
    final plain = HongguoResumePlayback.progress(
      seriesId: '100',
      episodeIds: episodeIds,
      local: local,
      cloud: cloud,
    );
    expect(plain?.episodeId, 'e1');
    final forced = HongguoResumePlayback.progress(
      seriesId: '100',
      episodeIds: episodeIds,
      local: local,
      cloud: cloud,
      preferCloud: true,
    );
    expect(forced?.episodeId, 'e2');
    const newerCloud = HongguoCloudProgress(
      seriesId: '100',
      episodeId: 'e2',
      episodeIndex: 1,
      position: 20,
      duration: 100,
      updatedAt: 1100,
    );
    final newer = HongguoResumePlayback.progress(
      seriesId: '100',
      episodeIds: episodeIds,
      local: local,
      cloud: newerCloud,
    );
    expect(newer?.episodeId, 'e2');
    const tiedCloud = HongguoCloudProgress(
      seriesId: '100',
      episodeId: 'e2',
      episodeIndex: 1,
      position: 20,
      duration: 100,
      updatedAt: 1000,
    );
    final tied = HongguoResumePlayback.progress(
      seriesId: '100',
      episodeIds: episodeIds,
      local: local,
      cloud: tiedCloud,
    );
    expect(tied?.episodeId, 'e1');
  });

  test('resume falls back to cloud episode index when ids differ', () {
    const cloud = HongguoCloudProgress(
      seriesId: '100',
      episodeId: 'other-site-e2',
      episodeIndex: 1,
      position: 30,
      duration: 100,
      updatedAt: 2000,
    );
    final result = HongguoResumePlayback.progress(
      seriesId: '100',
      episodeIds: const ['e1', 'e2'],
      cloud: cloud,
    );
    expect(result?.episodeId, 'e2');
    expect(result?.episodeIndex, 1);
    const outOfRange = HongguoCloudProgress(
      seriesId: '100',
      episodeId: 'other-site-e9',
      episodeIndex: 9,
      position: 30,
      duration: 100,
      updatedAt: 2000,
    );
    expect(
      HongguoResumePlayback.progress(
        seriesId: '100',
        episodeIds: const ['e1', 'e2'],
        cloud: outOfRange,
      ),
      isNull,
    );
  });

  test('resume target moves to next episode when completed', () {
    final done = HongguoResumePlayback.target(
      episodeIds: const ['e1', 'e2'],
      episodeId: 'e1',
      position: 95,
      completed: true,
    );
    expect(done.index, 1);
    expect(done.position, 0);
    final kept = HongguoResumePlayback.target(
      episodeIds: const ['e1', 'e2'],
      episodeId: 'e1',
      position: 50,
      completed: false,
    );
    expect(kept.index, 0);
    expect(kept.position, 50);
    final unknown = HongguoResumePlayback.target(
      episodeIds: const ['e1', 'e2'],
      episodeId: 'e9',
      position: 50,
      completed: false,
    );
    expect(unknown.index, 0);
    expect(unknown.position, 0);
  });

  test('cloud history parses raw rows and caps at 50', () {
    final rows = HongguoCloudProgress.parseList([
      {
        'series_id': '100',
        'vid': '12345',
        'vid_index': 2,
        'current_play_time': 30,
        'current_total_time': 100,
        'last_watch_time': 1700000000,
        'episode_count': 80,
      },
      {'series_id': 'bad', 'vid': 'x'},
    ]);
    expect(rows.length, 1);
    expect(rows.first.seriesId, '100');
    expect(rows.first.episodeIndex, 1);
    expect(rows.first.updatedAt, 1700000000000);
  });

  test('cloud favorites parse raw rows', () {
    final rows = HongguoCloudFavorite.parseList([
      {
        'series_id': '100',
        'series_title': '测试剧',
        'series_cover_url': 'https://example.invalid/cover.jpg',
        'collect_time': 1700000000,
      },
    ]);
    expect(rows.length, 1);
    expect(rows.first.drama.title, '测试剧');
    expect(rows.first.collectedAt, 1700000000000);
  });

  test('reservations split online and upcoming', () {
    final online = HongguoCloudReservation.parseList([
      {
        'series_id': '100',
        'series_title': '已上线剧',
        'is_online': true,
        'schedule_publish_time': 1700000000,
      },
    ], true);
    expect(online.length, 1);
    expect(online.first.online, isTrue);
    final upcoming = HongguoCloudReservation.parseList([
      {
        'item_id': '200',
        'name': '待上线剧',
        'is_online': false,
      },
    ], false);
    expect(upcoming.length, 1);
    expect(upcoming.first.drama.id, 'reservation:200');
  });

  test('favorite update is a high-water mark', () {
    final first = HongguoFavoriteUpdate.first(5, 1000);
    expect(first.added, 0);
    final grown = first.observe(7, 2000);
    expect(grown.added, 2);
    final shrunk = grown.observe(6, 3000);
    expect(shrunk.added, 1);
    expect(shrunk.total, 6);
    final acked = shrunk.observe(6, 4000, acknowledge: true);
    expect(acked.added, 0);
  });

  test('related seasons order by season and find next', () {
    final current = hongguoDrama('1', '测试剧第一季');
    final rows = HongguoRelated.fetchRelatedSeasons(
      current: current,
      candidates: [
        hongguoDrama('3', '测试剧第三季'),
        hongguoDrama('2', '测试剧第二季'),
        hongguoDrama('9', '别的剧第二季'),
      ],
    );
    expect(rows.map((row) => row.drama.id).toList(), ['2', '3']);
    final next = HongguoRelated.nextSeason(current: current, rows: rows);
    expect(next?.drama.id, '2');
    expect(next?.upcoming, isFalse);
    final remote = HongguoRelated.fetchRelatedSeasons(
      current: current,
      candidates: const [],
      remoteRows: [
        HongguoRelatedSeason(
          drama: hongguoDrama('4', '测试剧第四季'),
          season: 4,
          unit: '季',
          upcoming: true,
        ),
      ],
    );
    expect(remote.length, 1);
    expect(remote.first.label, contains('待上线'));
    expect(
      HongguoRelated.nextSeason(current: current, rows: remote),
      isNull,
    );
  });

  test('sendSmsCode maps rate limit error 7 to login failure', () async {
    final limited = GoHongguoAccountTransport(
      _SendSmsRepository('请求太频繁（错误码 7）'),
    );
    await expectLater(
      limited.sendSmsCode('13800138000'),
      throwsA(
        isA<HongguoLoginFailure>()
            .having((error) => error.errorCode, 'errorCode', 7)
            .having((error) => error.message, 'message', contains('60 秒')),
      ),
    );
    final plain = GoHongguoAccountTransport(
      _SendSmsRepository('验证码没发出去'),
    );
    await expectLater(
      plain.sendSmsCode('13800138000'),
      throwsA(isA<AppFailure>()),
    );
  });

  test('unavailable transport reports unwired Go actions', () async {
    await expectLater(
      HongguoAccountTransport.unavailable.sendSmsCode('13800138000'),
      throwsA(isA<HongguoAccountUnavailable>()),
    );
    await expectLater(
      HongguoAccountTransport.unavailable.fetchQrCode(),
      throwsA(isA<HongguoAccountUnavailable>()),
    );
  });
}
