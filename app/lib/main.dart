import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ui/key_screen.dart';

/// Starts Sounder with the Key_Screen as its only screen. REQ-KEY-6.
void main() => runApp(
  const ProviderScope(
    child: MaterialApp(
      title: 'Sounder',
      debugShowCheckedModeBanner: false,
      home: KeyScreen(),
    ),
  ),
);
