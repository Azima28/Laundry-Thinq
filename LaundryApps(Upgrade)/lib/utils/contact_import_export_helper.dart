import 'dart:convert';
import 'dart:io';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import '../database/models/customer_model.dart';
import '../database/models/database_helper.dart';

/// Representation of a parsed contact ready for import
class ParsedContact {
  String name;
  String phone;
  String? address;
  String? notes;
  String? email;
  bool isExisting;
  int? existingId;
  String? existingName;
  String sourceFormat; // 'vCard (.vcf)', 'Google Contacts CSV', 'Generic CSV', 'JSON'
  bool isSelected;

  ParsedContact({
    required this.name,
    required this.phone,
    this.address,
    this.notes,
    this.email,
    this.isExisting = false,
    this.existingId,
    this.existingName,
    required this.sourceFormat,
    this.isSelected = true,
  });

  Map<String, dynamic> toCustomerMap() {
    return {
      'id': existingId,
      'name': name.trim(),
      'phone': phone.trim(),
      'address': address != null && address!.trim().isNotEmpty ? address!.trim() : null,
      'created_at': DateTime.now().toIso8601String(),
    };
  }
}

/// Analysis report before committing to database
class ContactAnalysisReport {
  final List<ParsedContact> allParsed;
  final int totalFound;
  final int newCount;
  final int existingCount;
  final int invalidCount;
  final String detectedFormat;
  final List<String> warningLogs;

  ContactAnalysisReport({
    required this.allParsed,
    required this.totalFound,
    required this.newCount,
    required this.existingCount,
    required this.invalidCount,
    required this.detectedFormat,
    required this.warningLogs,
  });
}

/// Final summary result after import execution
class ImportResultSummary {
  final int totalProcessed;
  final int newlyAdded;
  final int updatedDuplicates;
  final int skippedDuplicates;
  final int invalidSkipped;
  final List<String> logs;

  ImportResultSummary({
    required this.totalProcessed,
    required this.newlyAdded,
    required this.updatedDuplicates,
    required this.skippedDuplicates,
    required this.invalidSkipped,
    required this.logs,
  });
}

class ContactImportExportHelper {
  static final DatabaseHelper _db = DatabaseHelper.instance;

  // ===========================================================================
  // 1. PHONE NUMBER SANITIZATION & NORMALIZATION
  // ===========================================================================
  static String normalizePhone(String rawPhone) {
    if (rawPhone.trim().isEmpty) return '';

    // Remove common separators, brackets, spaces, and punctuation
    String cleaned = rawPhone.replaceAll(RegExp(r'[\s\-()./,]+'), '').trim();
    if (cleaned.isEmpty) return '';

    // Remove any non-digits except leading +
    cleaned = cleaned.replaceAll(RegExp(r'[^0-9+]'), '');

    // Format to standard Indonesian/International E.164
    if (cleaned.startsWith('+62')) {
      return cleaned;
    } else if (cleaned.startsWith('62')) {
      return '+$cleaned';
    } else if (cleaned.startsWith('0')) {
      return '+62${cleaned.substring(1)}';
    } else if (cleaned.startsWith('8')) {
      return '+62$cleaned';
    } else if (cleaned.startsWith('+')) {
      return cleaned;
    } else {
      return '+62$cleaned';
    }
  }

  // ===========================================================================
  // 2. MULTI-FORMAT CONTACT PARSER
  // ===========================================================================

  /// Auto-detect format by extension or file signature
  static Future<ContactAnalysisReport> analyzeAndParseContent(
    String content, {
    String? fileName,
  }) async {
    final List<ParsedContact> rawContacts = [];
    final List<String> warnings = [];
    String detectedFormat = 'Teks / CSV';

    final cleanName = (fileName ?? '').toLowerCase();

    try {
      if (cleanName.endsWith('.vcf') || content.contains('BEGIN:VCARD')) {
        detectedFormat = 'vCard (.vcf) [Android / iOS / Google]';
        rawContacts.addAll(_parseVcf(content, warnings));
      } else if (cleanName.endsWith('.json') || (content.trim().startsWith('[') || content.trim().startsWith('{'))) {
        try {
          detectedFormat = 'JSON Backup';
          rawContacts.addAll(_parseJson(content, warnings));
        } catch (_) {
          // Fallback to CSV if JSON fails
          detectedFormat = 'CSV / Spreadsheet';
          rawContacts.addAll(_parseCsv(content, warnings));
        }
      } else {
        detectedFormat = 'CSV / Spreadsheet (Excel / Google)';
        rawContacts.addAll(_parseCsv(content, warnings));
      }
    } catch (e) {
      warnings.add('Error saat mem-parsing file: $e');
    }

    // Load existing customers from SQLite for duplicate detection
    final existingDbRows = await _db.getAllCustomers();
    final List<Customer> existingCustomers = existingDbRows.map((e) => Customer.fromMap(e)).toList();

    final Map<String, Customer> existingByNormalizedPhone = {};
    final Map<String, Customer> existingByCleanName = {};

    for (final c in existingCustomers) {
      final normP = normalizePhone(c.phone);
      if (normP.isNotEmpty) {
        existingByNormalizedPhone[normP] = c;
      }
      final cleanN = c.name.trim().toLowerCase();
      if (cleanN.isNotEmpty && cleanN != '-' && cleanN != 'pelanggan') {
        existingByCleanName[cleanN] = c;
      }
    }

    int newCount = 0;
    int existingCount = 0;
    int invalidCount = 0;

    final List<ParsedContact> validatedList = [];

    for (final pc in rawContacts) {
      final normPhone = normalizePhone(pc.phone);
      pc.phone = normPhone;

      // Validation: Must have at least a non-empty Name or a valid Phone
      if (pc.name.trim().isEmpty && normPhone.isEmpty) {
        invalidCount++;
        warnings.add('Melewati baris kosong / tidak valid tanpa nama dan nomor.');
        continue;
      }

      // If name is missing, use phone number as name
      if (pc.name.trim().isEmpty) {
        pc.name = 'Pelanggan $normPhone';
      }

      // Check if phone or name matches existing database
      Customer? match;
      if (normPhone.isNotEmpty && existingByNormalizedPhone.containsKey(normPhone)) {
        match = existingByNormalizedPhone[normPhone];
      } else if (normPhone.isEmpty && existingByCleanName.containsKey(pc.name.trim().toLowerCase())) {
        match = existingByCleanName[pc.name.trim().toLowerCase()];
      }

      if (match != null) {
        pc.isExisting = true;
        pc.existingId = match.id;
        pc.existingName = match.name;
        existingCount++;
      } else {
        pc.isExisting = false;
        newCount++;
      }

      validatedList.add(pc);
    }

    return ContactAnalysisReport(
      allParsed: validatedList,
      totalFound: validatedList.length,
      newCount: newCount,
      existingCount: existingCount,
      invalidCount: invalidCount,
      detectedFormat: detectedFormat,
      warningLogs: warnings,
    );
  }

  // ===========================================================================
  // 3. VCARD (.VCF) PARSER (iOS, Android, Samsung, Google)
  // ===========================================================================
  static List<ParsedContact> _parseVcf(String content, List<String> warnings) {
    final List<ParsedContact> contacts = [];

    // 1. Unfold multiline vCard fields (lines starting with space or tab continue previous line)
    final unfoldedContent = content.replaceAll(RegExp(r'\r\n[ \t]'), '').replaceAll(RegExp(r'\n[ \t]'), '');
    final lines = unfoldedContent.split(RegExp(r'\r?\n'));

    bool inVcard = false;
    String name = '';
    String phone = '';
    String? address;
    String? notes;
    String? email;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.toUpperCase() == 'BEGIN:VCARD') {
        inVcard = true;
        name = '';
        phone = '';
        address = null;
        notes = null;
        email = null;
        continue;
      }

      if (line.toUpperCase() == 'END:VCARD') {
        if (inVcard && (name.isNotEmpty || phone.isNotEmpty)) {
          contacts.add(ParsedContact(
            name: name.isNotEmpty ? name : 'Pelanggan $phone',
            phone: phone,
            address: address,
            notes: notes,
            email: email,
            sourceFormat: 'vCard (.vcf)',
          ));
        }
        inVcard = false;
        continue;
      }

      if (!inVcard) continue;

      final colonIdx = line.indexOf(':');
      if (colonIdx == -1) continue;

      final keyPart = line.substring(0, colonIdx).toUpperCase();
      String valPart = line.substring(colonIdx + 1).trim();

      // Decode Quoted-Printable if present
      if (keyPart.contains('ENCODING=QUOTED-PRINTABLE') || keyPart.contains('ENCODING=B')) {
        valPart = _decodeQuotedPrintable(valPart);
      }

      // Parse Full Name (FN) or Structured Name (N)
      if (keyPart.startsWith('FN')) {
        if (name.isEmpty || name.startsWith('Pelanggan')) {
          name = valPart.replaceAll(';', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        }
      } else if (keyPart.startsWith('N') && !keyPart.startsWith('NOTE')) {
        if (name.isEmpty) {
          // N:Family;Given;Middle;Prefix;Suffix
          final parts = valPart.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
          if (parts.length >= 2) {
            name = '${parts[1]} ${parts[0]}'.trim();
          } else if (parts.isNotEmpty) {
            name = parts[0];
          }
        }
      } else if (keyPart.startsWith('TEL')) {
        // Only set primary phone if empty or if preferred cell
        final cleanP = normalizePhone(valPart);
        if (cleanP.isNotEmpty) {
          if (phone.isEmpty || keyPart.contains('CELL') || keyPart.contains('PREF')) {
            phone = cleanP;
          }
        }
      } else if (keyPart.startsWith('ADR')) {
        // ADR:;;Street;City;Region;Postal;Country
        final parts = valPart.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
        if (parts.isNotEmpty) {
          address = parts.join(', ');
        }
      } else if (keyPart.startsWith('NOTE')) {
        notes = valPart;
      } else if (keyPart.startsWith('EMAIL')) {
        email = valPart;
      }
    }

    return contacts;
  }

  /// Decode Quoted-Printable string (e.g. =3D -> =, =D0=B0, etc.)
  static String _decodeQuotedPrintable(String input) {
    try {
      final bytes = <int>[];
      int i = 0;
      while (i < input.length) {
        if (input[i] == '=' && i + 2 < input.length) {
          final hex = input.substring(i + 1, i + 3);
          final byteVal = int.tryParse(hex, radix: 16);
          if (byteVal != null) {
            bytes.add(byteVal);
            i += 3;
            continue;
          }
        }
        bytes.add(input.codeUnitAt(i));
        i++;
      }
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return input;
    }
  }

  // ===========================================================================
  // 4. CSV & SPREADSHEET PARSER (Google Contacts, Excel, Outlook, Generic)
  // ===========================================================================
  static List<ParsedContact> _parseCsv(String content, List<String> warnings) {
    final List<ParsedContact> contacts = [];
    final lines = _splitCsvLines(content);
    if (lines.isEmpty) return contacts;

    // Detect delimiter from header (comma, semicolon, tab)
    final headerLine = lines.first;
    String delimiter = ',';
    final commaCount = headerLine.split(',').length;
    final semicolonCount = headerLine.split(';').length;
    final tabCount = headerLine.split('\t').length;

    if (semicolonCount > commaCount && semicolonCount > tabCount) {
      delimiter = ';';
    } else if (tabCount > commaCount && tabCount > semicolonCount) {
      delimiter = '\t';
    }

    final headers = _parseCsvRow(headerLine, delimiter).map((h) => h.trim().toLowerCase()).toList();

    // Find column index mappings
    int nameIdx = -1;
    int givenNameIdx = -1;
    int familyNameIdx = -1;
    int phoneIdx = -1;
    int altPhoneIdx = -1;
    int addressIdx = -1;
    int notesIdx = -1;
    int emailIdx = -1;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h == 'name' || h == 'nama' || h == 'full name' || h == 'nama pelanggan' || h == 'customer' || h == 'display name') {
        nameIdx = i;
      } else if (h == 'given name' || h == 'first name' || h == 'nama depan') {
        givenNameIdx = i;
      } else if (h == 'family name' || h == 'last name' || h == 'nama belakang') {
        familyNameIdx = i;
      } else if (h == 'phone 1 - value' || h == 'phone' || h == 'telepon' || h == 'no hp' || h == 'no wa' || h == 'nomor telepon' || h == 'mobile phone' || h == 'primary phone' || h == 'whatsapp' || h == 'telp' || h == 'hp') {
        if (phoneIdx == -1) phoneIdx = i;
      } else if (h == 'phone 2 - value' || h == 'phone 2' || h == 'home phone' || h == 'secondary phone') {
        altPhoneIdx = i;
      } else if (h.contains('address') || h.contains('alamat') || h.contains('street') || h.contains('lokasi')) {
        if (addressIdx == -1) addressIdx = i;
      } else if (h.contains('note') || h.contains('catatan') || h.contains('keterangan')) {
        notesIdx = i;
      } else if (h.contains('email') || h.contains('e-mail')) {
        emailIdx = i;
      }
    }

    // Process rows
    for (int r = 1; r < lines.length; r++) {
      final rowStr = lines[r].trim();
      if (rowStr.isEmpty) continue;

      final row = _parseCsvRow(rowStr, delimiter);
      if (row.isEmpty) continue;

      String name = '';
      if (nameIdx != -1 && nameIdx < row.length && row[nameIdx].trim().isNotEmpty) {
        name = row[nameIdx].trim();
      } else if (givenNameIdx != -1 && givenNameIdx < row.length) {
        final g = row[givenNameIdx].trim();
        final f = (familyNameIdx != -1 && familyNameIdx < row.length) ? row[familyNameIdx].trim() : '';
        name = '$g $f'.trim();
      }

      String phone = '';
      if (phoneIdx != -1 && phoneIdx < row.length && row[phoneIdx].trim().isNotEmpty) {
        phone = row[phoneIdx].trim();
      } else if (altPhoneIdx != -1 && altPhoneIdx < row.length && row[altPhoneIdx].trim().isNotEmpty) {
        phone = row[altPhoneIdx].trim();
      }

      // If columns weren't identified by header, use positional fallback (col 0 = name, col 1 = phone)
      if (name.isEmpty && phone.isEmpty && row.isNotEmpty) {
        if (row.length >= 2) {
          name = row[0].trim();
          phone = row[1].trim();
        } else if (row.length == 1) {
          final val = row[0].trim();
          if (RegExp(r'^[0-9+\s\-()]+$').hasMatch(val)) {
            phone = val;
          } else {
            name = val;
          }
        }
      }

      String? address;
      if (addressIdx != -1 && addressIdx < row.length && row[addressIdx].trim().isNotEmpty) {
        address = row[addressIdx].trim();
      }

      String? notes;
      if (notesIdx != -1 && notesIdx < row.length && row[notesIdx].trim().isNotEmpty) {
        notes = row[notesIdx].trim();
      }

      String? email;
      if (emailIdx != -1 && emailIdx < row.length && row[emailIdx].trim().isNotEmpty) {
        email = row[emailIdx].trim();
      }

      if (name.isNotEmpty || phone.isNotEmpty) {
        contacts.add(ParsedContact(
          name: name.isNotEmpty ? name : 'Pelanggan $phone',
          phone: phone,
          address: address,
          notes: notes,
          email: email,
          sourceFormat: 'CSV / Spreadsheet',
        ));
      }
    }

    return contacts;
  }

  /// Properly parse CSV row respecting quotes and commas
  static List<String> _parseCsvRow(String row, String delimiter) {
    final List<String> result = [];
    final StringBuffer current = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < row.length; i++) {
      final char = row[i];
      if (char == '"') {
        if (inQuotes && i + 1 < row.length && row[i + 1] == '"') {
          current.write('"');
          i++; // Skip escaped quote
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == delimiter && !inQuotes) {
        result.add(current.toString());
        current.clear();
      } else {
        current.write(char);
      }
    }
    result.add(current.toString());
    return result;
  }

  /// Split CSV lines preserving multiline quoted fields
  static List<String> _splitCsvLines(String content) {
    final List<String> lines = [];
    final StringBuffer currentLine = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '"') {
        if (inQuotes && i + 1 < content.length && content[i + 1] == '"') {
          currentLine.write('""');
          i++;
        } else {
          inQuotes = !inQuotes;
          currentLine.write('"');
        }
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++; // Skip \r\n
        }
        if (currentLine.isNotEmpty) {
          lines.add(currentLine.toString());
          currentLine.clear();
        }
      } else {
        currentLine.write(char);
      }
    }

    if (currentLine.isNotEmpty) {
      lines.add(currentLine.toString());
    }

    return lines;
  }

  // ===========================================================================
  // 5. JSON PARSER
  // ===========================================================================
  static List<ParsedContact> _parseJson(String content, List<String> warnings) {
    final List<ParsedContact> contacts = [];
    final decoded = json.decode(content);

    List<dynamic> items = [];
    if (decoded is List) {
      items = decoded;
    } else if (decoded is Map<String, dynamic>) {
      if (decoded['customers'] is List) {
        items = decoded['customers'] as List;
      } else if (decoded['data'] is List) {
        items = decoded['data'] as List;
      }
    }

    for (final it in items) {
      if (it is Map<String, dynamic>) {
        final name = (it['name'] ?? it['nama'] ?? it['customer_name'] ?? '').toString().trim();
        final phone = (it['phone'] ?? it['telepon'] ?? it['no_hp'] ?? it['whatsapp'] ?? '').toString().trim();
        final address = (it['address'] ?? it['alamat'] ?? '').toString().trim();
        final notes = (it['notes'] ?? it['catatan'] ?? '').toString().trim();

        if (name.isNotEmpty || phone.isNotEmpty) {
          contacts.add(ParsedContact(
            name: name.isNotEmpty ? name : 'Pelanggan $phone',
            phone: phone,
            address: address.isNotEmpty ? address : null,
            notes: notes.isNotEmpty ? notes : null,
            sourceFormat: 'JSON Backup',
          ));
        }
      }
    }

    return contacts;
  }

  // ===========================================================================
  // 6. ADDITIVE IMPORT EXECUTION (ADD & MERGE, NEVER OVERWRITE ALL)
  // ===========================================================================
  static Future<ImportResultSummary> executeImport({
    required List<ParsedContact> contacts,
    required bool updateDuplicates,
  }) async {
    int newlyAdded = 0;
    int updatedDuplicates = 0;
    int skippedDuplicates = 0;
    int invalidSkipped = 0;
    final List<String> logs = [];

    // Filter to selected items only
    final selectedContacts = contacts.where((c) => c.isSelected).toList();

    for (final contact in selectedContacts) {
      try {
        final normPhone = normalizePhone(contact.phone);
        final cleanName = contact.name.trim();

        if (cleanName.isEmpty && normPhone.isEmpty) {
          invalidSkipped++;
          continue;
        }

        if (contact.isExisting && contact.existingId != null) {
          if (updateDuplicates) {
            // Merge & enrich existing customer details without replacing their transaction history
            final existingData = await _db.getCustomer(contact.existingId!);
            if (existingData != null) {
              final existingCust = Customer.fromMap(existingData);

              // Use new address if existing was empty, or keep updated
              final mergedAddress = (contact.address != null && contact.address!.trim().isNotEmpty)
                  ? contact.address!.trim()
                  : existingCust.address;

              final updatedCustomer = existingCust.copyWith(
                name: cleanName.isNotEmpty ? cleanName : existingCust.name,
                phone: normPhone.isNotEmpty ? normPhone : existingCust.phone,
                address: mergedAddress,
              );

              await _db.updateCustomer(updatedCustomer.toMap());
              updatedDuplicates++;
              logs.add('Diperbarui: ${updatedCustomer.name} ($normPhone)');
            }
          } else {
            skippedDuplicates++;
          }
        } else {
          // Add brand new customer
          final newCustomer = Customer(
            name: cleanName.isNotEmpty ? cleanName : 'Pelanggan $normPhone',
            phone: normPhone,
            address: contact.address != null && contact.address!.trim().isNotEmpty ? contact.address!.trim() : null,
            createdAt: DateTime.now(),
          );

          await _db.insertCustomer(newCustomer.toMap());
          newlyAdded++;
          logs.add('Ditambahkan: ${newCustomer.name} ($normPhone)');
        }
      } catch (e) {
        logs.add('Gagal mengimpor "${contact.name}": $e');
      }
    }

    return ImportResultSummary(
      totalProcessed: selectedContacts.length,
      newlyAdded: newlyAdded,
      updatedDuplicates: updatedDuplicates,
      skippedDuplicates: skippedDuplicates,
      invalidSkipped: invalidSkipped,
      logs: logs,
    );
  }

  // ===========================================================================
  // 7. EXPORT FORMAT GENERATORS
  // ===========================================================================

  /// Export customers to Standard vCard (.vcf) format (Compatible with Android, Samsung, iOS/iCloud, Google)
  static String exportToVcf(List<Customer> customers) {
    final StringBuffer sb = StringBuffer();
    for (final c in customers) {
      sb.writeln('BEGIN:VCARD');
      sb.writeln('VERSION:3.0');
      sb.writeln('FN:${c.name}');
      sb.writeln('N:;${c.name};;;');
      if (c.phone.isNotEmpty) {
        sb.writeln('TEL;TYPE=CELL;TYPE=PREF;TYPE=VOICE:${c.phone}');
      }
      if (c.address != null && c.address!.trim().isNotEmpty) {
        sb.writeln('ADR;TYPE=HOME:;;${c.address!.replaceAll(';', ',')};;;;');
      }
      sb.writeln('NOTE:Pelanggan Smart Laundry POS');
      sb.writeln('END:VCARD');
    }
    return sb.toString();
  }

  /// Export customers to Standard CSV (Excel-Compatible UTF-8 with BOM)
  static String exportToCsv(List<Customer> customers) {
    final StringBuffer sb = StringBuffer();
    // Prepend UTF-8 BOM so Excel opens Indonesian & special characters without mangling
    sb.write('﻿');
    sb.writeln('Nama Pelanggan,Nomor WhatsApp,Alamat,Tanggal Dibuat');

    for (final c in customers) {
      final nameEscaped = '"${c.name.replaceAll('"', '""')}"';
      final phoneEscaped = '"${c.phone.replaceAll('"', '""')}"';
      final addressEscaped = '"${(c.address ?? '').replaceAll('"', '""')}"';
      final dateStr = '"${DateFormat('yyyy-MM-dd HH:mm').format(c.createdAt)}"';

      sb.writeln('$nameEscaped,$phoneEscaped,$addressEscaped,$dateStr');
    }
    return sb.toString();
  }

  /// Export customers to structured JSON backup
  static String exportToJson(List<Customer> customers) {
    final list = customers.map((c) => {
      'id': c.id,
      'name': c.name,
      'phone': c.phone,
      'address': c.address,
      'created_at': c.createdAt.toIso8601String(),
    }).toList();

    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'app': 'Smart Laundry POS',
      'export_date': DateTime.now().toIso8601String(),
      'total_customers': customers.length,
      'customers': list,
    });
  }

  /// Save exported file to Downloads or Documents directory
  static Future<File> saveExportFile({
    required String fileName,
    required String content,
  }) async {
    Directory? targetDir;
    try {
      targetDir = await getDownloadsDirectory();
    } catch (_) {}

    targetDir ??= await getApplicationDocumentsDirectory();

    final filePath = '${targetDir.path}${Platform.pathSeparator}$fileName';
    final file = File(filePath);
    await file.writeAsString(content, encoding: utf8);
    return file;
  }
}
