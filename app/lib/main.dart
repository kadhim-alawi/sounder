import 'package:flutter/material.dart';
import 'package:morse_core/morse_core.dart';

void main() => runApp(const SounderApp());

/// Temporary shell. Proves the app builds, deploys and uses morse_core.
class SounderApp extends StatelessWidget {
  const SounderApp({super.key});

  @override
  Widget build(BuildContext context) {
    const encoder = MorseEncoder();
    return MaterialApp(
      title: 'Sounder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Sounder', style: TextStyle(fontSize: 40)),
              const SizedBox(height: 16),
              Text(
                encoder.encode('SOS'),
                style: const TextStyle(fontSize: 32, fontFamily: 'monospace'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}