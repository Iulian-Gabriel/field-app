import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

void main() => runApp(const FieldApp());

class Building {
  final String id;
  final String address;
  final int? floors; // null = not surveyed yet
  final int? elevators;
  const Building({required this.id, required this.address, this.floors, this.elevators});

  Building copyWith({int? floors, int? elevators}) =>
      Building(id: id, address: address, floors: floors ?? this.floors, elevators: elevators ?? this.elevators);
}

String describe(Building b) {
  final floors = b.floors ?? 'unknown';
  final elevators = b.elevators ?? 'unknown';
  if(b.elevators == null){
    return '${b.address}: $floors floors, elevators $elevators';
  }
  return '${b.address}: $floors floors, $elevators elevators';
}

class FieldApp extends StatelessWidget {
  const FieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    const b = Building(id: 'b-17', address: 'Str. Lipscani 12');
    return MaterialApp(
      title: 'Field app',
      home: Scaffold(
        appBar: AppBar(title: const Text('Field app')),
        body: Center(child: Text(describe(b))),
      ),
    );
  }
}