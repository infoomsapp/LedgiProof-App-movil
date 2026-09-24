// Same Supabase project the LedgiProof web app uses (hceihybnqjpzqyibkznp).
// The anon key is meant to be public in a client app -- RLS on every table
// is what actually protects the data, same assumption the web app makes.
class SupabaseConfig {
  static const String url = 'https://hceihybnqjpzqyibkznp.supabase.co';
  static const String publishableKey = 'sb_publishable_7pEEGuxOpDPa712aGbzpaA_9Xv68fNZ';
}
