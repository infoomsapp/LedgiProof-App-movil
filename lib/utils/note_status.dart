/// Status of a workspace note -- same rules, same order as the web's
/// getWorkspaceNoteStatus (src/services/workspace-notes.service.ts), so a
/// note reads the same on the phone and at the desk.
enum NoteStatus { archived, approved, done, pendingApproval, open }

NoteStatus noteStatus({
  required DateTime? archivedAt,
  required DateTime? approvedAt,
  required DateTime? completedAt,
  required bool requiresApproval,
}) {
  if (archivedAt != null) return NoteStatus.archived;
  if (approvedAt != null) return NoteStatus.approved;
  if (completedAt != null) return NoteStatus.done;
  if (requiresApproval) return NoteStatus.pendingApproval;
  return NoteStatus.open;
}

String noteStatusLabel(NoteStatus s) => switch (s) {
      NoteStatus.archived => 'Archived',
      NoteStatus.approved => 'Approved',
      NoteStatus.done => 'Done',
      NoteStatus.pendingApproval => 'Pending approval',
      NoteStatus.open => 'Open',
    };

/// Who may approve: owner/admin/accountant, never the author (segregation of
/// duties -- approve_workspace_note enforces the same in the database).
bool canApproveNote({
  required NoteStatus status,
  required String role,
  required String createdBy,
  required String userId,
}) =>
    status == NoteStatus.pendingApproval &&
    const {'owner', 'admin', 'accountant'}.contains(role) &&
    createdBy != userId;

/// "Mark done" only for a live note that needs no approval.
bool canCompleteNote(NoteStatus status, bool requiresApproval) =>
    status == NoteStatus.open && !requiresApproval;
