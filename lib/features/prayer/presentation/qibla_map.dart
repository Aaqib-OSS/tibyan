import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/theme/app_theme.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/qibla.dart';
import 'qibla_screen.dart' show KaabaBadge;

/// The OpenStreetMap tile server; its policy asks for a real app identity.
const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _osmUserAgentPackage = 'app.tibyan.tibyan';

/// The computer's Qibla: a map with the great-circle line from the saved
/// place to the Kaaba, markers at both ends, and the OSM attribution.
/// Without tiles (offline, or the server fails) the line is drawn over a
/// plain background with a note.
class QiblaMap extends StatefulWidget {
  const QiblaMap({
    super.key,
    required this.lat,
    required this.lon,
    required this.placeLabel,
    this.tiles = true,
  });

  final double lat;
  final double lon;
  final String placeLabel;

  /// Whether to load OpenStreetMap tiles at all.
  final bool tiles;

  @override
  State<QiblaMap> createState() => _QiblaMapState();
}

class _QiblaMapState extends State<QiblaMap> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final t = context.tokens.colors;
    final offline = !widget.tiles || _failed;
    final path = [
      for (final p in kaabaGreatCircle(widget.lat, widget.lon))
        LatLng(p.lat, p.lon),
    ];
    final you = LatLng(widget.lat, widget.lon);
    const kaaba = LatLng(kaabaLat, kaabaLon);
    final bounds = LatLngBounds.fromPoints(path);
    final height = math.min(MediaQuery.sizeOf(context).height * .6, 520.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          key: const ValueKey('qibla-map'),
          label: l.qiblaMapLabel(widget.placeLabel),
          image: true,
          excludeSemantics: true,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(
              height: math.max(height, 280),
              child: FlutterMap(
                options: MapOptions(
                  initialCameraFit: CameraFit.bounds(
                    bounds: bounds,
                    padding: const EdgeInsets.all(48),
                    maxZoom: 9,
                  ),
                  backgroundColor: t.paper,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  if (!offline)
                    TileLayer(
                      urlTemplate: _osmTiles,
                      userAgentPackageName: _osmUserAgentPackage,
                      maxNativeZoom: 19,
                      errorTileCallback: (_, _, _) {
                        if (mounted && !_failed) {
                          setState(() => _failed = true);
                        }
                      },
                    ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: path,
                        strokeWidth: 5,
                        color: t.accent,
                        borderStrokeWidth: 2,
                        borderColor: t.paper,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: you,
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.my_location,
                          color: t.control,
                          size: 30,
                          semanticLabel: l.qiblaYou,
                        ),
                      ),
                      const Marker(
                        point: kaaba,
                        width: 48,
                        height: 48,
                        child: KaabaBadge(size: 48),
                      ),
                    ],
                  ),
                  if (!offline)
                    Align(
                      alignment: AlignmentDirectional.bottomEnd,
                      child: Container(
                        key: const ValueKey('qibla-osm-attribution'),
                        color: t.paper.withValues(alpha: .85),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          l.qiblaMapAttribution,
                          style: TextStyle(color: t.ink, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        if (offline) ...[
          const SizedBox(height: 8),
          Text(
            l.qiblaMapOffline,
            key: const ValueKey('qibla-map-offline'),
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted, height: 1.5),
          ),
        ],
      ],
    );
  }
}
