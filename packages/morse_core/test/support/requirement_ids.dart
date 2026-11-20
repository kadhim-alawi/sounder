/// Every requirement ID defined in `.kiro/specs/morse-core/requirements.md`.
///
/// Tests use this set to check that every requirement ID cited in a doc
/// comment exists (REQ-PURE-7). It is a copy so the test suite never reads
/// files outside `packages/morse_core/` (REQ-TEST-7). It deliberately imports
/// nothing, so a mistake in `lib/` cannot change the expected IDs.
///
/// Keep this set in sync: update it whenever `requirements.md` adds, removes
/// or renumbers a requirement ID.
///
/// Exactly 68 IDs: CODE 1-10, ENC 1-13, DEC 1-10, FMT 1-7, ERR 1-12,
/// PURE 1-9, TEST 1-7.
/// REQ-PURE-7, REQ-TEST-7.
library;

/// The 68 requirement IDs, grouped by requirement. REQ-PURE-7, REQ-TEST-7.
const Set<String> requirementIds = <String>{
  // Requirement 1: Code table.
  'REQ-CODE-1',
  'REQ-CODE-2',
  'REQ-CODE-3',
  'REQ-CODE-4',
  'REQ-CODE-5',
  'REQ-CODE-6',
  'REQ-CODE-7',
  'REQ-CODE-8',
  'REQ-CODE-9',
  'REQ-CODE-10',

  // Requirement 2: Encode text to Morse.
  'REQ-ENC-1',
  'REQ-ENC-2',
  'REQ-ENC-3',
  'REQ-ENC-4',
  'REQ-ENC-5',
  'REQ-ENC-6',
  'REQ-ENC-7',
  'REQ-ENC-8',
  'REQ-ENC-9',
  'REQ-ENC-10',
  'REQ-ENC-11',
  'REQ-ENC-12',
  'REQ-ENC-13',

  // Requirement 3: Decode Morse to text.
  'REQ-DEC-1',
  'REQ-DEC-2',
  'REQ-DEC-3',
  'REQ-DEC-4',
  'REQ-DEC-5',
  'REQ-DEC-6',
  'REQ-DEC-7',
  'REQ-DEC-8',
  'REQ-DEC-9',
  'REQ-DEC-10',

  // Requirement 4: Encoded text format.
  'REQ-FMT-1',
  'REQ-FMT-2',
  'REQ-FMT-3',
  'REQ-FMT-4',
  'REQ-FMT-5',
  'REQ-FMT-6',
  'REQ-FMT-7',

  // Requirement 5: Errors for invalid input.
  'REQ-ERR-1',
  'REQ-ERR-2',
  'REQ-ERR-3',
  'REQ-ERR-4',
  'REQ-ERR-5',
  'REQ-ERR-6',
  'REQ-ERR-7',
  'REQ-ERR-8',
  'REQ-ERR-9',
  'REQ-ERR-10',
  'REQ-ERR-11',
  'REQ-ERR-12',

  // Requirement 6: Package purity and structure.
  'REQ-PURE-1',
  'REQ-PURE-2',
  'REQ-PURE-3',
  'REQ-PURE-4',
  'REQ-PURE-5',
  'REQ-PURE-6',
  'REQ-PURE-7',
  'REQ-PURE-8',
  'REQ-PURE-9',

  // Requirement 7: Tests.
  'REQ-TEST-1',
  'REQ-TEST-2',
  'REQ-TEST-3',
  'REQ-TEST-4',
  'REQ-TEST-5',
  'REQ-TEST-6',
  'REQ-TEST-7',
};
