import 'dart:convert';
import 'dart:io';

import 'package:duanju_app/js_runtime/cheerio_js.dart';
import 'package:duanju_app/js_runtime/js_engine.dart';

const String _html =
    '<div class="wrap"><div class="card" id="first"><a href="/a1" data-kind="alpha">Alpha <b>Title</b></a><span class="tag">Hot</span></div>'
    '<div class="card skip"><a href="/a2" data-kind="beta">Beta Title</a><span class="tag">Cold</span></div>'
    '<div class="card"><a href="/a3" data-kind="gamma">Gamma Title</a><span class="tag">Hot</span></div></div>';

int _passed = 0;
int _failed = 0;

void _check(String name, bool condition) {
  if (condition) {
    _passed++;
    stdout.writeln('PASS $name');
  } else {
    _failed++;
    stdout.writeln('FAIL $name');
  }
}

Future<void> main() async {
  const String libPath = '/tmp/libquickjs.so';
  if (!File(libPath).existsSync()) {
    final ProcessResult built = await Process.run('sh', <String>[
      'lib/js_runtime/native/build_host_linux.sh',
      libPath,
    ]);
    if (built.exitCode != 0) {
      stdout.writeln('FAIL build libquickjs.so: ${built.stderr}');
      exitCode = 1;
      return;
    }
  }
  final String cheerioSource = File(
    'assets/js_runtime/cheerio.min.js',
  ).readAsStringSync();
  final QuickJsEngine engine = QuickJsEngine.open(libPath);
  try {
    engine.eval(CheerioJs.buildInstallScript(cheerioSource));
    String pdfh(String rule) {
      return engine.eval(
        'pdfh(${jsonEncode(_html)}, ${jsonEncode(rule)})',
      );
    }

    List<String> pdfa(String rule) {
      final String raw = engine.eval(
        'JSON.stringify(pdfa(${jsonEncode(_html)}, ${jsonEncode(rule)}))',
      );
      final List<dynamic> decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.map((dynamic value) => value.toString()).toList();
    }

    _check(
      'tag and class Text',
      pdfh('div.card && a && Text') == 'Alpha Title',
    );
    _check('id attribute', pdfh('#first && a && href') == '/a1');
    _check(
      'descendant chain Text',
      pdfh('div.wrap && div.card && a && Text') == 'Alpha Title',
    );
    _check(
      'matches Text',
      pdfh('div.card && a:matches(Beta) && Text') == 'Beta Title',
    );
    _check(
      'contains Text',
      pdfh('div.card && a:contains(Gamma) && Text') == 'Gamma Title',
    );
    _check(
      'Html field',
      pdfh('div.card && a && Html') == 'Alpha <b>Title</b>',
    );
    _check(
      'data attribute field',
      pdfh('#first && a && data-kind') == 'alpha',
    );
    _check(
      'missing attribute returns empty',
      pdfh('#first && a && data-missing') == '',
    );
    _check(
      'pdfh element without field returns outer html',
      pdfh('div.card').contains('id="first"') &&
          pdfh('div.card').contains('Alpha'),
    );
    final List<String> texts = pdfa('div.card && a && Text');
    _check(
      'pdfa Text list',
      texts.length == 3 &&
          texts[0] == 'Alpha Title' &&
          texts[1] == 'Beta Title' &&
          texts[2] == 'Gamma Title',
    );
    final List<String> hrefs = pdfa('div.card && a && href');
    _check(
      'pdfa attribute list',
      hrefs.length == 3 &&
          hrefs[0] == '/a1' &&
          hrefs[1] == '/a2' &&
          hrefs[2] == '/a3',
    );
    final List<String> kept = pdfa('div.card:not(.skip) && a && Text');
    _check(
      'pdfa not list',
      kept.length == 2 &&
          kept[0] == 'Alpha Title' &&
          kept[1] == 'Gamma Title',
    );
    final List<String> cards = pdfa('div.card');
    _check(
      'pdfa element list outer html',
      cards.length == 3 &&
          cards[0].contains('id="first"') &&
          cards[1].contains('skip') &&
          cards[2].contains('/a3'),
    );
    _check('pdfh empty returns empty', pdfh('div.missing && a && Text') == '');
    _check(
      'pdfa empty field list returns empty',
      pdfa('div.missing && a && Text').isEmpty,
    );
    _check('pdfa empty element list returns empty', pdfa('div.missing').isEmpty);
  } finally {
    engine.dispose();
  }
  stdout.writeln('RESULT $_passed passed, $_failed failed');
  if (_failed > 0) {
    exitCode = 1;
  }
}
