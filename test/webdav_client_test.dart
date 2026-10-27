import 'package:duanju_app/webdav_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('join appends the file name to base paths', () {
    expect(
      webdavJoinUrl('https://example.com/dav', 'backup.json'),
      'https://example.com/dav/backup.json',
    );
    expect(
      webdavJoinUrl('https://example.com/dav/', 'backup.json'),
      'https://example.com/dav/backup.json',
    );
    expect(
      webdavJoinUrl('https://user.example.com:8443/a/b', 'backup.json'),
      'https://user.example.com:8443/a/b/backup.json',
    );
  });

  test('address validation rejects empty and non-http addresses', () {
    expect(webdavValidateAddress(''), isNotNull);
    expect(webdavValidateAddress('ftp://example.com/dav'), isNotNull);
    expect(webdavValidateAddress('https://'), isNotNull);
    expect(webdavValidateAddress('https://example.com/dav'), isNull);
    expect(
      () => webdavJoinUrl('example.com/dav', 'backup.json'),
      throwsFormatException,
    );
  });

  test('basic auth header encodes credentials', () {
    expect(webdavBasicAuthHeader('user', 'pass'), 'Basic dXNlcjpwYXNz');
  });

  test('upload and download go through the injected transport', () async {
    var method = '';
    var url = '';
    var auth = '';
    final client = WebdavClient(
      baseUrl: 'https://example.com/dav/',
      username: 'user',
      password: 'pass',
      transport: (calledMethod, calledUrl, {headers, body}) async {
        method = calledMethod;
        url = calledUrl.toString();
        auth = headers?['Authorization'] ?? '';
        if (calledMethod == 'PUT') {
          expect(String.fromCharCodes(body!), '{"a":1}');
          return const WebdavResponse(201, []);
        }
        return WebdavResponse(200, '{"a":1}'.codeUnits);
      },
    );
    await client.upload('backup.json', '{"a":1}');
    expect(method, 'PUT');
    expect(url, 'https://example.com/dav/backup.json');
    expect(auth, 'Basic dXNlcjpwYXNz');
    final downloaded = await client.download('backup.json');
    expect(method, 'GET');
    expect(downloaded, '{"a":1}');
  });

  test('non-2xx responses surface as errors', () async {
    final client = WebdavClient(
      baseUrl: 'https://example.com/dav/',
      transport: (method, url, {headers, body}) async =>
          const WebdavResponse(404, []),
    );
    await expectLater(
      client.upload('backup.json', '{}'),
      throwsA(isA<WebdavException>()),
    );
    await expectLater(
      client.download('backup.json'),
      throwsA(isA<WebdavException>()),
    );
  });
}
