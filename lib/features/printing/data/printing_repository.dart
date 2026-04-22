import 'printing_models.dart';

abstract class PrintingRepository {
  Future<List<PrinterProfile>> fetchPrinters();

  Future<List<PrintTemplateProfile>> fetchTemplates({
    PrintDocumentType? documentType,
    PrintPaperSize? paperSize,
  });

  Future<List<PrintRoute>> fetchRoutes();

  Future<PrintJobRecord> createJob(PrintJobDraft draft);

  Future<void> updateJobStatus({
    required String jobId,
    required PrintJobStatus status,
    String? failureReason,
  });

  Future<List<PrintJobRecord>> fetchRecentJobs({int limit = 20});
}
