/// Every requirement ID defined in `.kiro/specs/adaptive-timing/requirements.md`.
///
/// Tests use this set, together with `requirementIds`, to check that every
/// requirement ID cited in a doc comment or at the start of a test name
/// exists (REQ-ENGINE-6, REQ-PBT-3). It is a copy so the test suite never
/// reads files outside `packages/morse_core/` (REQ-TEST-7). It deliberately
/// imports nothing, so a mistake in `lib/` cannot change the expected IDs.
///
/// Keep this set in sync: update it whenever the adaptive-timing
/// `requirements.md` adds, removes or renumbers a requirement ID.
///
/// Exactly 96 IDs: EVENT 1-6, DEBOUNCE 1-14 and 20-22, CAL 1-16, 20, 21, 30,
/// 31, TIMING 1-11, BATCH 1-12, LIVE 1-14, ENGINE 1-8, PBT 1-8.
/// REQ-ENGINE-6, REQ-PBT-3.
library;

/// The 96 requirement IDs, grouped by requirement. REQ-ENGINE-6, REQ-PBT-3.
const Set<String> timingRequirementIds = <String>{
  // Requirement 1: Switch events.
  'REQ-EVENT-1',
  'REQ-EVENT-2',
  'REQ-EVENT-3',
  'REQ-EVENT-4',
  'REQ-EVENT-5',
  'REQ-EVENT-6',

  // Requirements 2 and 3: Timing configuration and debounce.
  'REQ-DEBOUNCE-1',
  'REQ-DEBOUNCE-2',
  'REQ-DEBOUNCE-3',
  'REQ-DEBOUNCE-4',
  'REQ-DEBOUNCE-5',
  'REQ-DEBOUNCE-6',
  'REQ-DEBOUNCE-7',
  'REQ-DEBOUNCE-8',
  'REQ-DEBOUNCE-9',
  'REQ-DEBOUNCE-10',
  'REQ-DEBOUNCE-11',
  'REQ-DEBOUNCE-12',
  'REQ-DEBOUNCE-13',
  'REQ-DEBOUNCE-14',
  'REQ-DEBOUNCE-20',
  'REQ-DEBOUNCE-21',
  'REQ-DEBOUNCE-22',

  // Requirements 4 and 5: Calibration word and measurement.
  'REQ-CAL-1',
  'REQ-CAL-2',
  'REQ-CAL-3',
  'REQ-CAL-4',
  'REQ-CAL-5',
  'REQ-CAL-6',
  'REQ-CAL-7',
  'REQ-CAL-8',
  'REQ-CAL-9',
  'REQ-CAL-10',
  'REQ-CAL-11',
  'REQ-CAL-12',
  'REQ-CAL-13',
  'REQ-CAL-14',
  'REQ-CAL-15',
  'REQ-CAL-16',
  'REQ-CAL-20',
  'REQ-CAL-21',
  'REQ-CAL-30',
  'REQ-CAL-31',

  // Requirement 6: Classification.
  'REQ-TIMING-1',
  'REQ-TIMING-2',
  'REQ-TIMING-3',
  'REQ-TIMING-4',
  'REQ-TIMING-5',
  'REQ-TIMING-6',
  'REQ-TIMING-7',
  'REQ-TIMING-8',
  'REQ-TIMING-9',
  'REQ-TIMING-10',
  'REQ-TIMING-11',

  // Requirement 7: Batch decoding.
  'REQ-BATCH-1',
  'REQ-BATCH-2',
  'REQ-BATCH-3',
  'REQ-BATCH-4',
  'REQ-BATCH-5',
  'REQ-BATCH-6',
  'REQ-BATCH-7',
  'REQ-BATCH-8',
  'REQ-BATCH-9',
  'REQ-BATCH-10',
  'REQ-BATCH-11',
  'REQ-BATCH-12',

  // Requirement 8: Incremental decoding.
  'REQ-LIVE-1',
  'REQ-LIVE-2',
  'REQ-LIVE-3',
  'REQ-LIVE-4',
  'REQ-LIVE-5',
  'REQ-LIVE-6',
  'REQ-LIVE-7',
  'REQ-LIVE-8',
  'REQ-LIVE-9',
  'REQ-LIVE-10',
  'REQ-LIVE-11',
  'REQ-LIVE-12',
  'REQ-LIVE-13',
  'REQ-LIVE-14',

  // Requirement 9: Engine purity, structure and privacy.
  'REQ-ENGINE-1',
  'REQ-ENGINE-2',
  'REQ-ENGINE-3',
  'REQ-ENGINE-4',
  'REQ-ENGINE-5',
  'REQ-ENGINE-6',
  'REQ-ENGINE-7',
  'REQ-ENGINE-8',

  // Requirement 10: Tests.
  'REQ-PBT-1',
  'REQ-PBT-2',
  'REQ-PBT-3',
  'REQ-PBT-4',
  'REQ-PBT-5',
  'REQ-PBT-6',
  'REQ-PBT-7',
  'REQ-PBT-8',
};
