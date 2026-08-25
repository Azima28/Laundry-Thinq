import 'package:flutter_test/flutter_test.dart';
import 'package:laundry_apps/database/models/order_model.dart';
import 'package:laundry_apps/utils/tub_note_helper.dart';

void main() {
  group('TubNoteHelper Unit Tests', () {
    test('normalizeWeight normalizes various inputs properly', () {
      expect(TubNoteHelper.normalizeWeight('8'), '8 kg');
      expect(TubNoteHelper.normalizeWeight('8kg'), '8 kg');
      expect(TubNoteHelper.normalizeWeight('8 kg'), '8 kg');
      expect(TubNoteHelper.normalizeWeight('7.5'), '7.5 kg');
      expect(TubNoteHelper.normalizeWeight('7,5 kg'), '7.5 kg');
      expect(TubNoteHelper.normalizeWeight('   '), '');
    });

    test('formatTubNotes formats weights starting from index 1', () {
      final formatted = TubNoteHelper.formatTubNotes(
        weights: ['8kg', '7kg', '6.5kg'],
        startIndex: 1,
        prefix: 'Cuci',
      );
      expect(formatted, 'Cuci 1: 8 kg | Cuci 2: 7 kg | Cuci 3: 6.5 kg');
    });

    test('formatTubNotes formats weights starting from index 2 when free wash is split', () {
      final formatted = TubNoteHelper.formatTubNotes(
        weights: ['7kg', '6.5kg'],
        startIndex: 2,
        prefix: 'Cuci',
      );
      expect(formatted, 'Cuci 2: 7 kg | Cuci 3: 6.5 kg');
    });

    test('formatTubNotes attaches general customer note without leaking duplicates', () {
      final formatted = TubNoteHelper.formatTubNotes(
        weights: ['8kg'],
        startIndex: 1,
        generalNote: 'Pisahkan baju putih',
        prefix: 'Cuci',
      );
      expect(formatted, 'Pisahkan baju putih • Cuci 1: 8 kg');
    });

    test('parseItemTubNotes correctly extracts weights for single and multiple tubs', () {
      final parsedSingle = TubNoteHelper.parseItemTubNotes(
        'Cuci Gratis (Kupon) • Tabung 1: 8 kg',
        1,
      );
      expect(parsedSingle, ['8 kg']);

      final parsedSplit = TubNoteHelper.parseItemTubNotes(
        'Tabung 2: 7 kg | Tabung 3: 6.5 kg',
        2,
      );
      expect(parsedSplit, ['7 kg', '6.5 kg']);

      final parsedFull = TubNoteHelper.parseItemTubNotes(
        'Tabung 1: 8 kg | Tabung 2: 7 kg | Tabung 3: 6.5 kg',
        3,
      );
      expect(parsedFull, ['8 kg', '7 kg', '6.5 kg']);
    });

    test('getOrderTubNotes retrieves all tub weights in order across split items', () {
      final order = Order(
        id: 101,
        customerName: 'Budi Santoso',
        customerPhone: '+628123456789',
        orderDate: DateTime.now(),
        totalAmount: 20000,
        status: 'Proses',
        userId: 1,
        items: [
          OrderItem(
            itemId: 1,
            itemName: 'Cuci Kering (Gratis)',
            quantity: 1,
            price: 0,
            note: 'Cuci Gratis (Kupon) • Tabung 1: 8 kg',
            machineType: 'cuci',
          ),
          OrderItem(
            itemId: 1,
            itemName: 'Cuci Kering',
            quantity: 2,
            price: 10000,
            note: 'Tabung 2: 7 kg | Tabung 3: 6.5 kg',
            machineType: 'cuci',
          ),
        ],
      );

      final tubNotes = TubNoteHelper.getOrderTubNotes(order, machineType: 'cuci');
      expect(tubNotes, ['8 kg', '7 kg', '6.5 kg']);
    });

    test('cleanCustomerNote strips internal tub weights and keeps customer instructions', () {
      expect(
        TubNoteHelper.cleanCustomerNote('Pisahkan baju putih • Tabung 1: 8 kg | Tabung 2: 7 kg'),
        'Pisahkan baju putih',
      );
      expect(
        TubNoteHelper.cleanCustomerNote('Tabung 1: 8 kg | Tabung 2: 7 kg | Tabung 3: 6.5 kg'),
        '',
      );
      expect(
        TubNoteHelper.cleanCustomerNote('Cuci Gratis (Kupon) • Tabung 1: 8 kg'),
        '',
      );
      expect(
        TubNoteHelper.cleanCustomerNote('Parfum lavender ekstra'),
        'Parfum lavender ekstra',
      );
    });

    test('formatForDisplay converts legacy Tabung to Cuci or Kering dynamically', () {
      expect(
        TubNoteHelper.formatForDisplay('Tabung 1: 6.4 kg', itemName: 'kering'),
        'Kering 1: 6.4 kg',
      );
      expect(
        TubNoteHelper.formatForDisplay('Tabung 1: 1.1 kg', itemName: 'cuci'),
        'Cuci 1: 1.1 kg',
      );
      expect(
        TubNoteHelper.formatForDisplay('Tabung 1: 8 kg | Tabung 2: 7 kg', itemName: 'cuci'),
        'Cuci 1: 8 kg | Cuci 2: 7 kg',
      );
    });
  });
}
