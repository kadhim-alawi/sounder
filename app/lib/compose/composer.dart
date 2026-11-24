import 'package:morse_core/morse_core.dart';

/// The Spell mode Composer: holds the Sentence as an ordered list of
/// Decoded_Items. Pure Dart: no Flutter, no clock, no timer, no I/O.
/// The Sentence changes only through [append], [undo] and [clear].
/// REQ-COMPOSE-1, REQ-COMPOSE-2, REQ-COMPOSE-3, REQ-COMPOSE-4,
/// REQ-COMPOSE-5.
final class Composer {
  /// Creates a Composer with an empty Sentence. REQ-COMPOSE-2.
  Composer();

  final List<DecodedItem> _items = <DecodedItem>[];

  /// The Sentence, oldest item first, as an unmodifiable list. Callers
  /// cannot change the Sentence through it. REQ-COMPOSE-2, REQ-COMPOSE-5.
  List<DecodedItem> get sentence => List<DecodedItem>.unmodifiable(_items);

  /// Appends [item] to the end of the Sentence, leaving every earlier item
  /// unchanged and in order. REQ-COMPOSE-2.
  void append(DecodedItem item) {
    _items.add(item);
  }

  /// Removes only the last item of the Sentence. Does nothing and raises
  /// no error when the Sentence is empty. REQ-COMPOSE-3.
  void undo() {
    if (_items.isNotEmpty) {
      _items.removeLast();
    }
  }

  /// Makes the Sentence empty. Raises no error when it is already empty.
  /// REQ-COMPOSE-4.
  void clear() {
    _items.clear();
  }
}
