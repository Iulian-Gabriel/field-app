import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:device_info_plus/device_info_plus.dart';

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
    return MaterialApp(
      title: 'Field app',
      home: const HomeScreen()
    );
  }
}

class HomeScreen extends StatelessWidget{
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    const b = Building(id: 'b-17', address: 'Str. Lipscani 12');
    return Scaffold(
      appBar: AppBar(title: const Text ('Field app')),
      body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Hello from Flutter on $platform'),
          Text(describe(b)),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeviceInfoScreen()),
            ),
            child: const Text('Device info'),
          )
        ],
      ),
    ),
    );
  }
}

Future<Map<String, String>> loadDeviceInfo() async {
  final plugin = DeviceInfoPlugin();
  if (kIsWeb) {
    final w = await plugin.webBrowserInfo;
    return {
      'os': 'n/a (running in a browser: ${w.browserName.name})',
      'model' : 'n/a (web)',
    };
  }
  switch (defaultTargetPlatform){
    case TargetPlatform.android:
      final a = await plugin.androidInfo;
      return {
        'os': 'Android ${a.version.release} (API ${a.version.sdkInt})',
        'model': '${a.manufacturer} ${a.model}',
      };
    case TargetPlatform.iOS:
      final i = await plugin.iosInfo;
      return {'os': '${i.systemName} ${i.systemVersion}', 'model': i.utsname.machine};
    default:
      return {'os': 'n/a', 'model': 'n/a'};
  }
}

class DeviceInfoScreen extends StatelessWidget{
  const DeviceInfoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    final size = MediaQuery.sizeOf(context);
    final ratio = MediaQuery.devicePixelRatioOf(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Device info')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, String>>(
          future: loadDeviceInfo(),
          builder: (context, snapshot) {
            final info = snapshot.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Platform: $platform'),
                Text('OS version: ${info?['os'] ?? 'loading...'}'),
                Text('Screen: ${size.width.round()} x ${size.height.round()} logical px'),
                Text('Pixel ratio: ${ratio.toStringAsFixed(2)}'),
                Text('Model: ${info?['model'] ?? 'loading...'}'),
              ],
            );
          },
        ),
      ),
    );
  }
}