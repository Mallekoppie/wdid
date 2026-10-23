import '../models/app_settings.dart';
import '../models/check_in.dart';
import '../models/drafts.dart';
import '../models/initiative.dart';
import '../models/note.dart';
import '../models/work_item.dart';

class ExportBundle {
  const ExportBundle({required this.directory, required this.files});

  final String directory;
  final Map<String, String> files;
}

class BackupStatus {
  const BackupStatus({required this.createdAt, required this.bytes});

  final DateTime createdAt;
  final int bytes;
}

/// Raised when the UI reaches a capability owned by a service that has not
/// landed in this build yet. The client must surface this instead of inventing
/// local behaviour.
class ServicePendingException implements Exception {
  const ServicePendingException(this.service, this.message);

  final String service;
  final String message;

  @override
  String toString() => '$service: $message';
}

/// Contract consumed by the UI.
///
/// Each method maps to the service capabilities documented in `plan.md`. The
/// Flutter client never computes authoritative totals or validation; the demo
/// adapter implements this interface only so the UI can run before the Go
/// service is connected.
abstract class WdidRepository {
  Future<List<Initiative>> listInitiatives();

  Future<Initiative> createInitiative(InitiativeDraft draft);

  Future<Initiative> updateInitiative(Initiative initiative);

  Future<List<WorkItem>> listWorkItems();

  Future<WorkItem> createWorkItem(WorkItemDraft draft);

  Future<WorkItem> updateWorkItem(WorkItem item);

  Future<void> deleteWorkItem(String id);

  Future<List<Note>> listNotes();

  Future<Note> createNote(NoteDraft draft);

  Future<Note> updateNote(Note note);

  Future<List<CheckIn>> listCheckIns();

  Future<CheckIn> createCheckIn(CheckInDraft draft);

  Future<CheckIn> updateCheckIn(CheckIn checkIn);

  Future<CheckIn> generateSummary(String checkInId);

  Future<String> buildPrompt(DateTime periodStart, DateTime periodEnd);

  Future<ExportBundle> buildExport(DateTime periodStart, DateTime periodEnd);

  Future<AppSettings> getSettings();

  Future<AppSettings> updateSettings(AppSettings settings);

  Future<BackupStatus> backupNow();
}
