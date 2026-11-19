// Throwaway spike. Answers two questions:
// 1. Can we measure Space-bar press durations accurately in the browser?
// 2. Can we speak a sentence with text-to-speech in the browser?
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

void main() {
  runApp(const KeySpikeApp());
}

class KeySpikeApp extends StatelessWidget {
  const KeySpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Key spike',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo)),
      home: const KeySpikePage(),
    );
  }
}

/// Spike-only threshold. Not for the real engine, which must use the calibrated unit.
const int _dahThresholdMs = 200;
const int _maxRows = 20;
const String _sentence = 'I want some water';

class _Press {
  _Press({required this.durationMs, required this.gapMs});

  final double durationMs;

  /// Time from the previous release to this press. Null for the first press.
  final double? gapMs;

  bool get isDah => durationMs >= _dahThresholdMs;
  String get symbol => isDah ? '-' : '.';
}

enum _SpeechState { idle, requested, speaking, succeeded, failed }

class KeySpikePage extends StatefulWidget {
  const KeySpikePage({super.key});

  @override
  State<KeySpikePage> createState() => _KeySpikePageState();
}

class _KeySpikePageState extends State<KeySpikePage> {
  final FocusNode _keyFocus = FocusNode(debugLabel: 'space key listener');
  final FlutterTts _tts = FlutterTts();

  // Key timing, all from KeyEvent.timeStamp.
  Duration? _downAt;
  Duration? _lastUpAt;
  final List<_Press> _presses = []; // newest first, capped at _maxRows
  String _pattern = '';
  int _repeatsIgnored = 0;
  bool _sawZeroTimestamp = false;

  // Speech.
  _SpeechState _speechState = _SpeechState.idle;
  String _speechDetail = 'Not tried yet.';
  Timer? _speechWatchdog;

  @override
  void initState() {
    super.initState();
    _tts.setStartHandler(() {
      _speechWatchdog?.cancel();
      _setSpeech(_SpeechState.speaking, 'Speaking (start event received)…');
    });
    _tts.setCompletionHandler(() {
      _speechWatchdog?.cancel();
      _setSpeech(_SpeechState.succeeded, 'Finished speaking "$_sentence".');
    });
    _tts.setErrorHandler((dynamic message) {
      _speechWatchdog?.cancel();
      _setSpeech(_SpeechState.failed, 'Error event: $message');
    });
  }

  @override
  void dispose() {
    _speechWatchdog?.cancel();
    _tts.stop();
    _keyFocus.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    if (event.timeStamp == Duration.zero) {
      _sawZeroTimestamp = true;
    }

    if (event is KeyRepeatEvent) {
      setState(() => _repeatsIgnored++);
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent) {
      // If a release was lost (e.g. window lost focus), this down starts fresh.
      setState(() => _downAt = event.timeStamp);
      return KeyEventResult.handled;
    }

    if (event is KeyUpEvent) {
      final downAt = _downAt;
      if (downAt == null) return KeyEventResult.handled; // up without a down
      final upAt = event.timeStamp;
      final durationMs = _ms(upAt - downAt);
      final lastUp = _lastUpAt;
      final gapMs = lastUp == null ? null : _ms(downAt - lastUp);
      setState(() {
        final press = _Press(durationMs: durationMs, gapMs: gapMs);
        _presses.insert(0, press);
        if (_presses.length > _maxRows) _presses.removeLast();
        _pattern += press.symbol;
        _downAt = null;
        _lastUpAt = upAt;
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  static double _ms(Duration d) => d.inMicroseconds / 1000.0;

  void _clear() {
    setState(() {
      _presses.clear();
      _pattern = '';
      _downAt = null;
      _lastUpAt = null;
      _repeatsIgnored = 0;
      _sawZeroTimestamp = false;
    });
    _keyFocus.requestFocus();
  }

  Future<void> _speak() async {
    _keyFocus.requestFocus();
    _speechWatchdog?.cancel();
    _setSpeech(_SpeechState.requested, 'Requested, waiting for the browser to start…');
    // The web plugin reports failure only through the error event, and some
    // browsers fail silently. Report that case instead of waiting forever.
    _speechWatchdog = Timer(const Duration(seconds: 5), () {
      if (_speechState == _SpeechState.requested) {
        _setSpeech(
          _SpeechState.failed,
          'No start event after 5 s. The browser may have no voice installed, '
          'blocked speech, or does not support the Web Speech API.',
        );
      }
    });
    try {
      await _tts.setLanguage('en-US');
      final result = await _tts.speak(_sentence);
      if (_speechState == _SpeechState.requested && result != null && result != 1) {
        _setSpeech(_SpeechState.requested, 'speak() returned $result, waiting for start event…');
      }
    } catch (e) {
      _speechWatchdog?.cancel();
      _setSpeech(_SpeechState.failed, 'Exception: $e');
    }
  }

  void _setSpeech(_SpeechState state, String detail) {
    if (!mounted) return;
    setState(() {
      _speechState = state;
      _speechDetail = detail;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _speechState == _SpeechState.requested || _speechState == _SpeechState.speaking;

    return Scaffold(
      appBar: AppBar(title: const Text('Key + speech spike')),
      body: Focus(
        focusNode: _keyFocus,
        autofocus: true,
        onKeyEvent: _onKeyEvent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _keyFocus.requestFocus,
          child: Padding(
            padding: const EdgeInsets.all(16),
            // ExcludeFocus keeps the buttons from taking keyboard focus, so
            // Space always reaches the listener instead of activating a button.
            child: ExcludeFocus(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: _keyFocus,
                    builder: (context, _) => Text(
                      _keyFocus.hasFocus
                          ? 'Listening. Press and hold Space. Under $_dahThresholdMs ms = dit, otherwise dah.'
                          : 'Not listening. Click anywhere on the page, then press Space.',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Key down: ${_downAt == null ? "no" : "yes"}   '
                    'Repeat events ignored: $_repeatsIgnored',
                  ),
                  if (_sawZeroTimestamp)
                    Text(
                      'Warning: saw a KeyEvent with timeStamp == 0. Timings may be invalid.',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: SelectableText(
                      _pattern.isEmpty ? ' ' : _pattern,
                      style: const TextStyle(fontSize: 56, fontFamily: 'monospace', letterSpacing: 6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _clear,
                        icon: const Icon(Icons.clear),
                        label: const Text('Clear'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: busy ? null : _speak,
                        icon: const Icon(Icons.volume_up),
                        label: const Text('Speak "$_sentence"'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Speech: ${_speechState.name.toUpperCase()}. $_speechDetail',
                    style: TextStyle(
                      color: switch (_speechState) {
                        _SpeechState.failed => theme.colorScheme.error,
                        _SpeechState.succeeded => Colors.green.shade800,
                        _ => null,
                      },
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Divider(height: 32),
                  Text('Last $_maxRows presses (newest first)', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  const _Row(cells: ['#', 'Press (ms)', 'Gap before (ms)', 'Symbol'], bold: true),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _presses.length,
                      itemBuilder: (context, i) {
                        final p = _presses[i];
                        return _Row(cells: [
                          '${i + 1}',
                          p.durationMs.toStringAsFixed(1),
                          p.gapMs?.toStringAsFixed(1) ?? '—',
                          p.isDah ? 'dah' : 'dit',
                        ]);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.cells, this.bold = false});

  final List<String> cells;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'monospace',
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 40, child: Text(cells[0], style: style)),
          for (final c in cells.skip(1)) Expanded(child: Text(c, style: style)),
        ],
      ),
    );
  }
}
