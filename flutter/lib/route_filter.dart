import 'contract/contract.dart';

/// status: 'todo' | 'done' | 'skipped', or null for All.
List<RouteStop> filterStops(List<RouteStop> stops, String? status) =>
    status == null ? stops : stops.where((s) => s.status.name == status).toList();