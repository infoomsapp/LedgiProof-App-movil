import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/utils/note_status.dart';

void main() {
  final now = DateTime(2026, 9, 29);

  test('status follows the web order: archived, approved, done, pending, open', () {
    expect(noteStatus(archivedAt: now, approvedAt: now, completedAt: now, requiresApproval: true), NoteStatus.archived);
    expect(noteStatus(archivedAt: null, approvedAt: now, completedAt: null, requiresApproval: true), NoteStatus.approved);
    expect(noteStatus(archivedAt: null, approvedAt: null, completedAt: now, requiresApproval: false), NoteStatus.done);
    expect(noteStatus(archivedAt: null, approvedAt: null, completedAt: null, requiresApproval: true),
        NoteStatus.pendingApproval);
    expect(noteStatus(archivedAt: null, approvedAt: null, completedAt: null, requiresApproval: false), NoteStatus.open);
  });

  test('the author never approves their own note', () {
    expect(canApproveNote(status: NoteStatus.pendingApproval, role: 'owner', createdBy: 'u1', userId: 'u1'), isFalse);
    expect(canApproveNote(status: NoteStatus.pendingApproval, role: 'owner', createdBy: 'u1', userId: 'u2'), isTrue);
    expect(canApproveNote(status: NoteStatus.pendingApproval, role: 'readonly', createdBy: 'u1', userId: 'u2'), isFalse);
  });

  test('mark done only for a live note that needs no approval', () {
    expect(canCompleteNote(NoteStatus.open, false), isTrue);
    expect(canCompleteNote(NoteStatus.pendingApproval, true), isFalse);
    expect(canCompleteNote(NoteStatus.archived, false), isFalse);
  });
}
