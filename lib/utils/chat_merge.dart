/// Result of folding a freshly fetched "latest page" into what is on screen.
class ChatMerge<T> {
  final List<T> messages;

  /// True when older pages the user already loaded were kept, so the caller
  /// must keep its existing pagination cursor rather than take the page's.
  final bool keptOlder;
  const ChatMerge(this.messages, this.keptOlder);
}

/// [current] and [fetched] are both oldest-first; [fetched] is the newest page
/// the server returned and [fetchedHasMore] says whether anything older than
/// it exists. Mirrors the web app's mergeLatestPage (src/lib/chat-merge.ts).
///
/// - The page is the whole thread, or shares nothing with the screen: it
///   replaces everything (keeping older pages would leave a gap).
/// - The page's first message is already on screen after older loaded ones:
///   keep those and swap in the fresh tail.
ChatMerge<T> mergeLatestPage<T>(
  List<T> current,
  List<T> fetched,
  bool fetchedHasMore,
  String Function(T) idOf,
) {
  if (!fetchedHasMore || fetched.isEmpty) {
    return ChatMerge(List<T>.of(fetched), false);
  }
  final firstId = idOf(fetched.first);
  final at = current.indexWhere((m) => idOf(m) == firstId);
  if (at > 0) {
    return ChatMerge([...current.take(at), ...fetched], true);
  }
  return ChatMerge(List<T>.of(fetched), false);
}
