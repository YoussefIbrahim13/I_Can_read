import 'dart:io';

import '../integration_test/support/minimal_pdf.dart';

/// Writes a blank PDF with a given page count, for manual testing of the
/// add-book flow without needing a real book on hand.
///
///   dart run tool/make_sample_pdf.dart 240 sample-book.pdf
void main(List<String> args) {
  final pageCount = int.tryParse(args.elementAtOrNull(0) ?? '') ?? 100;
  final path = args.elementAtOrNull(1) ?? 'sample-book.pdf';

  final bytes = minimalPdf(pageCount: pageCount);
  File(path).writeAsBytesSync(bytes);

  stdout.writeln('Wrote $path — $pageCount pages, ${bytes.length} bytes');
}
