import 'print_dispatch_payload_builder.dart';
import 'printing_models.dart';
import 'printing_template_service.dart';
import 'quote_print_document_adapter.dart';
import 'sale_print_job_preparation_service.dart';

class QuotePrintJobPreparationService {
  const QuotePrintJobPreparationService({
    this.documentAdapter = const QuotePrintDocumentAdapter(),
    this.templateService = const PrintingTemplateService(),
    this.payloadBuilder = const PrintDispatchPayloadBuilder(),
  });

  final QuotePrintDocumentAdapter documentAdapter;
  final PrintingTemplateService templateService;
  final PrintDispatchPayloadBuilder payloadBuilder;

  PreparedPrintJobData prepareQuotePreview({
    required QuotePrintSource quote,
    PrintPaperSize paperSize = PrintPaperSize.a4,
    String? printerId,
    String? templateId,
    int copies = 1,
  }) {
    final document = documentAdapter.toDocumentData(quote);
    final idempotencyKey =
        'quote:${quote.quoteId}:${_paperSizeValue(paperSize)}:v1';
    final jobPayload = payloadBuilder.buildPrintJobPayload(
      document: document,
      paperSize: paperSize,
      printerId: printerId,
      templateId: templateId,
      sourceTable: 'quotations',
      sourceId: quote.quoteId,
      copies: copies,
      idempotencyKey: idempotencyKey,
    );

    switch (paperSize) {
      case PrintPaperSize.thermal80mm:
        final template =
            templateService.buildThermal80Template(document, copies: copies);
        return PreparedPrintJobData(
          document: document,
          paperSize: paperSize,
          thermalTemplate: template,
          dispatchPayload: jobPayload,
          job: PrintJobDraft(
            branchId: quote.branchId,
            documentType: document.documentType,
            paperSize: paperSize,
            printerId: printerId,
            templateId: templateId,
            sourceTable: 'quotations',
            sourceId: quote.quoteId,
            copies: copies,
            idempotencyKey: idempotencyKey,
            payload: jobPayload,
          ),
        );
      case PrintPaperSize.a4:
        final template = templateService.buildA4Template(document);
        final a4Payload = payloadBuilder.buildA4Payload(
          document: document,
          template: template,
          printerId: printerId,
          templateId: templateId,
        );
        return PreparedPrintJobData(
          document: document,
          paperSize: paperSize,
          a4Template: template,
          dispatchPayload: a4Payload,
          job: PrintJobDraft(
            branchId: quote.branchId,
            documentType: document.documentType,
            paperSize: paperSize,
            printerId: printerId,
            templateId: templateId,
            sourceTable: 'quotations',
            sourceId: quote.quoteId,
            copies: copies,
            idempotencyKey: idempotencyKey,
            payload: jobPayload,
          ),
        );
    }
  }
}

String _paperSizeValue(PrintPaperSize value) {
  return switch (value) {
    PrintPaperSize.thermal80mm => 'thermal_80mm',
    PrintPaperSize.a4 => 'a4',
  };
}
