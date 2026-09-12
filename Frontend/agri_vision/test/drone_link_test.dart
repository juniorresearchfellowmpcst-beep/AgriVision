import 'package:flutter_test/flutter_test.dart';

import 'package:agri_vision/src/domain/entity/telemetry_entity.dart';
import 'package:agri_vision/src/ui/widget/drone/flight_controls.dart';

/// The small decisions the drone screens make about a real link — the ones
/// that decide whether an operator can connect a radio, and what the buttons
/// over a flying aircraft say.
void main() {
  group('the address of a link', () {
    test('a serial port is the case where the speed has to be set', () {
      for (final address in ['COM5', 'com12', '/dev/ttyUSB0', '/dev/ttyACM0']) {
        expect(isSerialAddress(address), isTrue, reason: address);
      }
      for (final address in [
        'udpin:0.0.0.0:14550',
        'tcp:127.0.0.1:5762',
        'udpout:192.168.1.9:14550',
        '',
      ]) {
        expect(isSerialAddress(address), isFalse, reason: address);
      }
    });

    test('every preset that is a serial port carries a speed', () {
      // A radio preset without a baud rate is a preset that cannot connect.
      for (final preset in mavlinkPresets) {
        expect(
          preset.baud != null,
          isSerialAddress(preset.url),
          reason: preset.label,
        );
      }
    });
  });

  group('the flight mode decides what the button offers', () {
    test('stopped and waiting means the next tap is Resume', () {
      for (final mode in ['BRAKE', 'LOITER', 'HOLD', 'GUIDED', 'brake']) {
        expect(isHoldingMode(mode), isTrue, reason: mode);
      }
    });

    test('flying the mission, or coming down, means the next tap is Hold', () {
      for (final mode in ['AUTO', 'RTL', 'LAND', null]) {
        expect(isHoldingMode(mode), isFalse, reason: '$mode');
      }
    });
  });

  group('what the backend says about the vehicle', () {
    test('an ArduPilot aircraft is flyable, and says what it is', () {
      final status = MavlinkStatusEntity.fromJson(const {
        'connected': true,
        'alive': true,
        'autopilot': 'ardupilot',
        'vehicle_type': 'quadrotor',
        'flight_control_supported': true,
        'mission_kind': 'spray',
        'telemetry': {'armed': true, 'gps_fix': 3, 'satellites': 14},
      });

      expect(status.flightControlSupported, isTrue);
      expect(status.autopilot, 'ardupilot');
      expect(status.vehicleType, 'quadrotor');
      expect(status.missionKind, 'spray');
      expect(status.telemetry.armed, isTrue);
    });

    test('a PX4 aircraft still reports, and reports as not flyable', () {
      final status = MavlinkStatusEntity.fromJson(const {
        'connected': true,
        'alive': true,
        'autopilot': 'px4',
        'flight_control_supported': false,
      });

      expect(status.flightControlSupported, isFalse);
      expect(status.autopilot, 'px4');
    });

    test('the newest warning is the one worth showing over a live map', () {
      final status = MavlinkStatusEntity.fromJson(const {
        'messages': [
          {'severity': 4, 'text': 'PreArm: GPS not healthy', 'age_s': 240.0},
          {'severity': 6, 'text': 'Mission: 3 WP', 'age_s': 1.0},
          {'severity': 2, 'text': 'Battery failsafe', 'age_s': 3.0},
        ],
      });

      expect(status.latestWarning?.text, 'Battery failsafe');
    });

    test('a warning from four minutes ago is not shown as news', () {
      final status = MavlinkStatusEntity.fromJson(const {
        'messages': [
          {'severity': 3, 'text': 'EKF variance', 'age_s': 240.0},
        ],
      });

      expect(status.latestWarning, isNull);
    });

    test('the pre-flight answer carries the reasons, not just a flag', () {
      final report = PreflightReport.fromJson(const {
        'ready': false,
        'problems': ['No 3-D GPS fix yet (2-D fix only, 5 satellites).'],
        'connected': true,
        'alive': true,
        'telemetry': {'gps_fix': 2, 'satellites': 5},
      });

      expect(report.ready, isFalse);
      expect(report.problems.single, contains('GPS'));
      expect(report.link.telemetry.satellites, 5);
    });
  });
}
