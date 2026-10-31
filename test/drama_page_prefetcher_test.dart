import 'dart:async';

import 'package:duanju_app/drama_page_prefetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetches pages serially until the list ends', () async {
    final prefetcher = DramaPagePrefetcher();
    var pages = 0;
    var concurrent = 0;
    var maxConcurrent = 0;
    await prefetcher.run(
      isCurrent: () => pages < 3,
      isBusy: () => false,
      loadMore: () async {
        concurrent++;
        if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        concurrent--;
        pages++;
        return true;
      },
    );
    expect(pages, 3);
    expect(maxConcurrent, 1);
    expect(prefetcher.running, isFalse);
  });

  test('stops after five prefetched pages', () async {
    final prefetcher = DramaPagePrefetcher();
    var pages = 0;
    await prefetcher.run(
      isCurrent: () => true,
      isBusy: () => false,
      loadMore: () async {
        pages++;
        return true;
      },
    );
    expect(pages, 5);
    expect(prefetcher.running, isFalse);
  });

  test('stops when a page makes no progress', () async {
    final prefetcher = DramaPagePrefetcher();
    var calls = 0;
    await prefetcher.run(
      isCurrent: () => true,
      isBusy: () => false,
      loadMore: () async {
        calls++;
        return false;
      },
    );
    expect(calls, 1);
  });

  test('waits while a load is already in flight', () async {
    final prefetcher = DramaPagePrefetcher();
    var busyChecks = 0;
    var calls = 0;
    await prefetcher.run(
      isCurrent: () => calls == 0,
      isBusy: () {
        busyChecks++;
        return busyChecks <= 1;
      },
      loadMore: () async {
        calls++;
        return true;
      },
    );
    expect(busyChecks, greaterThanOrEqualTo(2));
    expect(calls, 1);
  });

  test('a second run while running returns immediately', () async {
    final prefetcher = DramaPagePrefetcher();
    final gate = Completer<void>();
    var calls = 0;
    final first = prefetcher.run(
      isCurrent: () => true,
      isBusy: () => false,
      loadMore: () async {
        calls++;
        await gate.future;
        return false;
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await prefetcher.run(
      isCurrent: () => true,
      isBusy: () => false,
      loadMore: () async => true,
    );
    expect(calls, 1);
    gate.complete();
    await first;
    expect(calls, 1);
  });

  test('stops when the list identity changes mid-run', () async {
    final prefetcher = DramaPagePrefetcher();
    var calls = 0;
    var current = true;
    await prefetcher.run(
      isCurrent: () => current,
      isBusy: () => false,
      loadMore: () async {
        calls++;
        current = false;
        return true;
      },
    );
    expect(calls, 1);
  });
}
