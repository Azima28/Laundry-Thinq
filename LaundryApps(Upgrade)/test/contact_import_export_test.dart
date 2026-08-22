import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:laundry_apps/database/models/customer_model.dart';
import 'package:laundry_apps/utils/contact_import_export_helper.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('ContactImportExportHelper Tests', () {
    test('Phone normalization handles all Indonesian & international variations', () {
      expect(ContactImportExportHelper.normalizePhone('081234567890'), '+6281234567890');
      expect(ContactImportExportHelper.normalizePhone('6281234567890'), '+6281234567890');
      expect(ContactImportExportHelper.normalizePhone('+6281234567890'), '+6281234567890');
      expect(ContactImportExportHelper.normalizePhone('812-3456-7890'), '+6281234567890');
      expect(ContactImportExportHelper.normalizePhone('+62 812 3456 7890'), '+6281234567890');
      expect(ContactImportExportHelper.normalizePhone('(0812) 3456-7890'), '+6281234567890');
      expect(ContactImportExportHelper.normalizePhone(''), '');
    });

    test('vCard .vcf parser parses iOS, Android, and Samsung contacts', () async {
      const vcfData = '''
BEGIN:VCARD
VERSION:3.0
FN:Budi Santoso
N:Santoso;Budi;;;
TEL;TYPE=CELL;TYPE=PREF:+628123456789
ADR;TYPE=HOME:;;Jl. Mawar No 12;Jakarta;DKI;12345;Indonesia
NOTE:Pelanggan VIP Laundry
END:VCARD
BEGIN:VCARD
VERSION:2.1
FN:Siti Aminah
TEL;CELL:089876543210
END:VCARD
''';

      final report = await ContactImportExportHelper.analyzeAndParseContent(vcfData, fileName: 'contacts.vcf');
      expect(report.totalFound, 2);
      expect(report.allParsed[0].name, 'Budi Santoso');
      expect(report.allParsed[0].phone, '+628123456789');
      expect(report.allParsed[0].address, 'Jl. Mawar No 12, Jakarta, DKI, 12345, Indonesia');
      expect(report.allParsed[1].name, 'Siti Aminah');
      expect(report.allParsed[1].phone, '+6289876543210');
    });

    test('CSV parser parses Google Contacts & Excel CSV', () async {
      const googleCsv = '''
Name,Given Name,Family Name,Phone 1 - Value,Address 1 - Formatted
Agus Pratama,Agus,Pratama,+628111222333,Jl. Melati No 5 Bandung
Dewi Lestari,Dewi,Lestari,08555666777,Komplek Permata Indah
''';

      final report = await ContactImportExportHelper.analyzeAndParseContent(googleCsv, fileName: 'google_contacts.csv');
      expect(report.totalFound, 2);
      expect(report.allParsed[0].name, 'Agus Pratama');
      expect(report.allParsed[0].phone, '+628111222333');
      expect(report.allParsed[0].address, 'Jl. Melati No 5 Bandung');
      expect(report.allParsed[1].name, 'Dewi Lestari');
      expect(report.allParsed[1].phone, '+628555666777');
    });

    test('Generic Indonesian CSV parsing', () async {
      const indoCsv = '''
Nama,No WA,Alamat
Rudi Hermawan,081299887766,Jl. Sudirman 10
Maya Sari,087711223344,Perum Citra Blok A2
''';

      final report = await ContactImportExportHelper.analyzeAndParseContent(indoCsv, fileName: 'pelanggan.csv');
      expect(report.totalFound, 2);
      expect(report.allParsed[0].name, 'Rudi Hermawan');
      expect(report.allParsed[0].phone, '+6281299887766');
      expect(report.allParsed[1].name, 'Maya Sari');
      expect(report.allParsed[1].phone, '+6287711223344');
    });

    test('JSON contact parsing', () async {
      const jsonData = '''
[
  {"name": "Kevin Sanjaya", "phone": "081344556677", "address": "Komp Bulutangkis"},
  {"nama": "Marcus Gideon", "telepon": "081988776655", "alamat": "Jakarta Barat"}
]
''';

      final report = await ContactImportExportHelper.analyzeAndParseContent(jsonData, fileName: 'contacts.json');
      expect(report.totalFound, 2);
      expect(report.allParsed[0].name, 'Kevin Sanjaya');
      expect(report.allParsed[0].phone, '+6281344556677');
      expect(report.allParsed[1].name, 'Marcus Gideon');
      expect(report.allParsed[1].phone, '+6281988776655');
    });

    test('Export to vCard and CSV produces valid formatting', () {
      final customers = [
        Customer(name: 'Anton Rahardjo', phone: '+6289522584477', address: 'Jl. Melati', createdAt: DateTime(2026, 8, 22)),
      ];

      final vcfOut = ContactImportExportHelper.exportToVcf(customers);
      expect(vcfOut.contains('BEGIN:VCARD'), true);
      expect(vcfOut.contains('FN:Anton Rahardjo'), true);
      expect(vcfOut.contains('TEL;TYPE=CELL;TYPE=PREF;TYPE=VOICE:+6289522584477'), true);
      expect(vcfOut.contains('END:VCARD'), true);

      final csvOut = ContactImportExportHelper.exportToCsv(customers);
      expect(csvOut.contains('Nama Pelanggan,Nomor WhatsApp,Alamat,Tanggal Dibuat'), true);
      expect(csvOut.contains('"Anton Rahardjo"'), true);
      expect(csvOut.contains('"+6289522584477"'), true);
    });
  });
}
