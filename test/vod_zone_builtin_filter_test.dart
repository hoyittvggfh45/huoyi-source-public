import 'package:duanju_app/home_screen.dart';
import 'package:duanju_app/models.dart';
import 'package:flutter_test/flutter_test.dart';

SourceSite videoSite(
  String id, {
  String origin = SourceSite.originConfig,
  String configId = '',
  String importType = '',
}) =>
    SourceSite(
      id,
      id,
      '',
      section: SourceSite.sectionVideo,
      origin: origin,
      configId: configId,
      importType: importType,
    );

void main() {
  test('builtin zoo and luna configs are hidden from the vod zone', () {
    expect(
      vodZoneShowsSource(videoSite('zoo_site', configId: 'zoo_main')),
      isFalse,
    );
    expect(
      vodZoneShowsSource(videoSite('luna_site', configId: 'luna_main')),
      isFalse,
    );
  });

  test('user imported config and py sources stay in the vod zone', () {
    expect(
      vodZoneShowsSource(videoSite('user_site', configId: 'user_cfg')),
      isTrue,
    );
    expect(
      vodZoneShowsSource(
        videoSite(
          'user_py',
          origin: SourceSite.originImport,
          importType: 'py',
        ),
      ),
      isTrue,
    );
  });

  test('builtin video and drama section sources stay out of the vod zone', () {
    expect(
      vodZoneShowsSource(
        videoSite('builtin_video', origin: SourceSite.originBuiltin),
      ),
      isFalse,
    );
    expect(
      vodZoneShowsSource(
        SourceSite(
          'drama_cfg',
          'drama_cfg',
          '',
          section: SourceSite.sectionDrama,
          origin: SourceSite.originConfig,
          configId: 'user_cfg',
        ),
      ),
      isFalse,
    );
  });
}
