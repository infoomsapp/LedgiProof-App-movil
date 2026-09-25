// Refreshing a thread (realtime, resume, reconnect) must not throw away older
// pages the user already scrolled back and loaded, and must never leave a gap.

import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/utils/chat_merge.dart';

List<String> ids(ChatMerge<String> r) => r.messages;
ChatMerge<String> merge(List<String> cur, List<String> fet, bool more) =>
    mergeLatestPage<String>(cur, fet, more, (s) => s);

void main() {
  test('keeps older pages and swaps in the fresh tail', () {
    final r = merge(
      ['a1', 'a2', 'b1', 'b2', 'b3'],
      ['b1', 'b2', 'b3', 'b4'],
      true,
    );
    expect(ids(r), ['a1', 'a2', 'b1', 'b2', 'b3', 'b4']);
    expect(r.keptOlder, isTrue);
  });

  test('replaces everything when the thread fits in one page', () {
    final r = merge(['b1', 'b2'], ['b1', 'b2', 'b3'], false);
    expect(ids(r), ['b1', 'b2', 'b3']);
    expect(r.keptOlder, isFalse);
  });

  test('takes the page as-is when nothing older is loaded', () {
    final r = merge(['b1', 'b2'], ['b1', 'b2', 'b3'], true);
    expect(ids(r), ['b1', 'b2', 'b3']);
    expect(r.keptOlder, isFalse);
  });

  test('drops old pages instead of leaving a gap', () {
    final r = merge(['a1', 'a2'], ['z1', 'z2', 'z3'], true);
    expect(ids(r), ['z1', 'z2', 'z3']);
    expect(r.keptOlder, isFalse);
  });

  test('empty fetch and empty screen', () {
    expect(ids(merge(['a1'], [], true)), isEmpty);
    expect(ids(merge([], ['b1'], true)), ['b1']);
  });

  test('does not mutate its inputs', () {
    final cur = ['a1', 'b1'];
    final fet = ['b1', 'b2'];
    merge(cur, fet, true);
    expect(cur, ['a1', 'b1']);
    expect(fet, ['b1', 'b2']);
  });
}
