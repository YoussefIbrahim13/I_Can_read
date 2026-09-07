import 'dart:convert';
import 'dart:typed_data';

/// Builds a real, structurally valid PDF with [pageCount] blank pages.
///
/// Used to exercise the actual PDF engine rather than a stub, without shipping
/// a binary fixture or touching any file that belongs to the user.
///
/// The cross-reference table is computed from real byte offsets, so a lenient
/// parser is not required to read it.
Uint8List minimalPdf({required int pageCount}) {
  if (pageCount < 1) {
    throw ArgumentError.value(pageCount, 'pageCount', 'must be at least 1');
  }

  final bytes = BytesBuilder();
  // Offset of each indirect object, indexed by object number.
  final offsets = <int, int>{};

  void write(String text) => bytes.add(ascii.encode(text));

  void writeObject(int number, String body) {
    offsets[number] = bytes.length;
    write('$number 0 obj\n$body\nendobj\n');
  }

  // Page objects are numbered from 3 upward; 1 is the catalog, 2 the page tree.
  final pageNumbers = [for (var i = 0; i < pageCount; i++) 3 + i];
  final kids = pageNumbers.map((n) => '$n 0 R').join(' ');

  write('%PDF-1.4\n');
  writeObject(1, '<< /Type /Catalog /Pages 2 0 R >>');
  writeObject(2, '<< /Type /Pages /Kids [$kids] /Count $pageCount >>');
  for (final number in pageNumbers) {
    writeObject(
      number,
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >>',
    );
  }

  final objectCount = pageCount + 3; // objects 1..N plus the free entry 0
  final xrefOffset = bytes.length;

  write('xref\n0 $objectCount\n');
  // Entries are fixed-width at exactly 20 bytes; the spec depends on it.
  write('0000000000 65535 f \n');
  for (var number = 1; number < objectCount; number++) {
    final offset = offsets[number]!.toString().padLeft(10, '0');
    write('$offset 00000 n \n');
  }

  write('trailer\n<< /Size $objectCount /Root 1 0 R >>\n');
  write('startxref\n$xrefOffset\n%%EOF\n');

  return bytes.toBytes();
}
