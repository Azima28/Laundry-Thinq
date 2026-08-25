import '../database/models/order_model.dart';

class TubNoteHelper {
  /// Normalizes a raw weight input string like "8", "8kg", "8.5", "8.5 kg" into "8 kg" or "8.5 kg".
  static String normalizeWeight(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final cleaned = trimmed.replaceAll(RegExp(r'\s*kg$', caseSensitive: false), '').trim();
    if (cleaned.isEmpty) return '';
    // If it's a number (int or double), format cleanly with kg
    final numVal = double.tryParse(cleaned.replaceAll(',', '.'));
    if (numVal != null) {
      if (numVal == numVal.toInt()) {
        return '${numVal.toInt()} kg';
      } else {
        return '$numVal kg';
      }
    }
    return '$cleaned kg';
  }

  /// Formats a list of weights for tubs into a standard string:
  /// e.g. "Tabung 1: 8 kg | Tabung 2: 7 kg | Tabung 3: 6.5 kg"
  static String formatTubNotes({
    required List<String> weights,
    int startIndex = 1,
    String? generalNote,
  }) {
    final List<String> segments = [];
    for (int i = 0; i < weights.length; i++) {
      final w = normalizeWeight(weights[i]);
      final tubNum = startIndex + i;
      if (w.isNotEmpty) {
        segments.add('Tabung $tubNum: $w');
      }
    }

    final tubPart = segments.join(' | ');
    final cleanGeneral = (generalNote != null) ? cleanCustomerNote(generalNote) : '';

    if (tubPart.isNotEmpty && cleanGeneral.isNotEmpty) {
      return '$cleanGeneral • $tubPart';
    } else if (tubPart.isNotEmpty) {
      return tubPart;
    } else {
      return cleanGeneral;
    }
  }

  /// Parses an OrderItem.note string and returns a List of per-tub weights for this item.
  /// Length of the returned list will be [quantity].
  static List<String> parseItemTubNotes(String? note, int quantity) {
    if (quantity <= 0) return [];
    final List<String> result = List.filled(quantity, '');
    if (note == null || note.trim().isEmpty) return result;

    final str = note.trim();

    // Match all patterns like "Tabung 1: 8 kg" or "Tabung 2: 7kg" or "Cuci 1: 8 kg"
    final regex = RegExp(
      r'(?:Tabung|Cuci|Kering)\s*(\d+)\s*:\s*([^|•\[\]\n\r]+)',
      caseSensitive: false,
    );
    final matches = regex.allMatches(str).toList();

    if (matches.isNotEmpty) {
      // Find the minimum tub number in this note to handle relative indexing
      int minTubNum = 999999;
      for (final m in matches) {
        final tubNum = int.tryParse(m.group(1) ?? '') ?? 1;
        if (tubNum < minTubNum) minTubNum = tubNum;
      }
      if (minTubNum == 999999) minTubNum = 1;

      for (final m in matches) {
        final tubNum = int.tryParse(m.group(1) ?? '') ?? 1;
        final weightStr = normalizeWeight(m.group(2) ?? '');
        final targetIndex = tubNum - minTubNum;
        if (targetIndex >= 0 && targetIndex < quantity) {
          result[targetIndex] = weightStr;
        }
      }
      return result;
    }

    // Fallback: If no "Tabung X:" pattern was found, but there's a simple weight string and quantity == 1
    if (quantity == 1) {
      final norm = normalizeWeight(str);
      if (norm.isNotEmpty) {
        result[0] = norm;
      }
    }

    return result;
  }

  /// Extracts all tub weights across all items matching [machineType] ('cuci' or 'pengering') for an [Order].
  static List<String> getOrderTubNotes(Order order, {required String machineType}) {
    final mType = machineType.toLowerCase();
    final matchingItems = order.items.where((it) {
      final name = it.itemName.toLowerCase();
      final itemMType = (it.machineType ?? '').toLowerCase();
      if (mType == 'cuci') {
        return itemMType == 'cuci' || name.contains('cuci') || name.contains('wash');
      } else if (mType == 'pengering' || mType == 'kering') {
        return itemMType == 'pengering' ||
            itemMType == 'kering' ||
            name.contains('kering') ||
            name.contains('pengering') ||
            name.contains('dry');
      }
      return itemMType == mType || name.contains(mType);
    }).toList();

    final List<String> allTubWeights = [];
    for (final item in matchingItems) {
      final tubNotes = parseItemTubNotes(item.note, item.quantity);
      allTubWeights.addAll(tubNotes);
    }
    return allTubWeights;
  }

  /// Strips internal tub notes and kupon markers from a note string so only public customer instructions remain.
  static String cleanCustomerNote(String? note) {
    if (note == null || note.trim().isEmpty) return '';
    String cleaned = note;
    // Remove "Cuci Gratis (Kupon)" markers
    cleaned = cleaned.replaceAll(RegExp(r'Cuci\s*Gratis\s*\(Kupon\)', caseSensitive: false), '');
    // Remove "Tabung X: ..." / "Cuci X: ..." / "Kering X: ..."
    cleaned = cleaned.replaceAll(
      RegExp(r'(?:Tabung|Cuci|Kering)\s*\d+\s*:[^|•\[\]\n\r]+', caseSensitive: false),
      '',
    );
    // Remove [TUB]...[/TUB] tags if any
    cleaned = cleaned.replaceAll(RegExp(r'\[TUB\].*?\[/TUB\]', caseSensitive: false), '');
    // Clean remaining separators and bullets
    cleaned = cleaned.replaceAll(RegExp(r'[|•]+'), ' ');
    cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }
}
