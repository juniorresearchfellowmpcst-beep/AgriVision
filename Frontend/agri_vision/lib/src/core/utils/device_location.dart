import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Outcome of asking the device where it is.
///
/// A fix and a failure are different things and the caller has to be able to
/// tell them apart: "GPS is off", "you said no" and "no fix yet" all need
/// different words on screen, and none of them may be shown as a position.
class DeviceLocationResult {
  const DeviceLocationResult._({
    this.position,
    this.accuracyMetres,
    this.error,
    this.canOpenSettings = false,
    this.servicesDisabled = false,
  });

  const DeviceLocationResult.success({
    required LatLng position,
    double? accuracyMetres,
  }) : this._(position: position, accuracyMetres: accuracyMetres);

  const DeviceLocationResult.failure(
    String error, {
    bool canOpenSettings = false,
    bool servicesDisabled = false,
  }) : this._(
         error: error,
         canOpenSettings: canOpenSettings,
         servicesDisabled: servicesDisabled,
       );

  final LatLng? position;

  /// Reported horizontal accuracy in metres, when the platform gives one.
  final double? accuracyMetres;

  /// Human-readable reason the fix could not be taken.
  final String? error;

  /// True when the fix failed for a reason the user fixes in system settings
  /// (services switched off, or permission denied for good).
  final bool canOpenSettings;

  /// True when location services are off device-wide, as opposed to this app
  /// being denied — they live on different settings screens.
  final bool servicesDisabled;

  bool get isSuccess => position != null;
}

/// Thin wrapper over geolocator that runs the permission dance once and
/// returns something a screen can render directly.
class DeviceLocation {
  const DeviceLocation._();

  /// Asks the device for a current fix, requesting permission if needed.
  ///
  /// Falls back to the last known position when a fresh fix times out, so
  /// pressing the button under a tin roof still puts the pin somewhere useful
  /// rather than doing nothing.
  static Future<DeviceLocationResult> current({
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const DeviceLocationResult.failure(
        'Location services are turned off on this device.',
        canOpenSettings: true,
        servicesDisabled: true,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      return const DeviceLocationResult.failure(
        'Location permission denied — the map cannot show where you are.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      return const DeviceLocationResult.failure(
        'Location permission is permanently denied. Enable it for AgriVision '
        'in system settings.',
        canOpenSettings: true,
      );
    }

    try {
      final fix = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
      return DeviceLocationResult.success(
        position: LatLng(fix.latitude, fix.longitude),
        accuracyMetres: fix.accuracy,
      );
    } catch (e) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) {
        return DeviceLocationResult.success(
          position: LatLng(last.latitude, last.longitude),
          accuracyMetres: last.accuracy,
        );
      }
      return DeviceLocationResult.failure(
        'Could not get a GPS fix: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }

  /// Opens the OS screen where the blocked setting actually lives.
  static Future<void> openSettings({required bool servicesOff}) => servicesOff
      ? Geolocator.openLocationSettings()
      : Geolocator.openAppSettings();
}
