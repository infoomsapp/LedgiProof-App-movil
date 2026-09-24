import 'package:supabase_flutter/supabase_flutter.dart';

/// Mirrors the web's src/lib/errors.ts / supabase/functions/_shared/errors.ts:
/// a raw exception's own `.message` can describe more of the schema than any
/// UI should show a user (column names, constraint names, internal RPC
/// detail) -- callers show THIS, never `e.toString()` / `'$e'` directly.
///
/// Only PostgrestException/AuthException/FunctionException/StorageException
/// (the four exception types supabase_flutter actually throws for a
/// database/auth/edge-function/storage call) are ever DB-shaped and thus
/// ever redacted. A plain StateError/Exception this app itself throws with a
/// deliberately short, safe message (e.g. `StateError('No session')`) is
/// shown as-is, the same way the web's safeMessage() trusts its own
/// `throw new Error(...)` call sites.
String friendlyError(Object error, [String fallback = 'Something went wrong. Please try again.']) {
  if (error is PostgrestException) {
    final code = error.code;
    return code != null ? (_codeMessages[code] ?? fallback) : fallback;
  }
  // Auth errors are the one exception-type exception: Supabase writes these
  // messages ("Invalid login credentials", "Email not confirmed", ...)
  // specifically to be shown to the end user, the same way login_screen.dart
  // already trusted `e.message` on AuthException before this file existed.
  if (error is AuthException) return error.message;
  if (error is FunctionException || error is StorageException) return fallback;
  if (error is StateError) return error.message;
  // Anything else unrecognized (a bare Error, a third-party exception type,
  // etc.) defaults to the safe fallback rather than risking its message
  // leaking internal detail -- the opposite default of web's safeMessage(),
  // which trusts a bare `Error` because Dart's `StateError` already covers
  // this app's own deliberate throw sites.
  return fallback;
}

const _codeMessages = <String, String>{
  '23505': 'This already exists.',
  '23503': "This can't be completed because it's linked to other records.",
  '23514': "That value isn't allowed for this field.",
  '42501': "You don't have permission to do that.",
  '22P02': 'One of the values entered is not valid.',
  'PGRST116': 'Not found.',
};
