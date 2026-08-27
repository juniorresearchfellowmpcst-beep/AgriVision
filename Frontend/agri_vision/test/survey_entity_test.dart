import 'package:flutter_test/flutter_test.dart';

import 'package:agri_vision/src/domain/entity/crop_catalog.dart';
import 'package:agri_vision/src/domain/entity/survey_entity.dart';
import 'package:agri_vision/src/domain/entity/treatment_entity.dart';

/// Parsing tests for the survey models.
///
/// These are not "does fromJson work" tests. Each one guards a distinction the
/// UI acts on, where getting it wrong sends a drone out to spray the wrong
/// thing or hides the reason it should not fly at all.
void main() {
  group('SprayProduct', () {
    test('a missing drone_ready flag means yes, not no', () {
      // Only the entries that are *not* sprays say so explicitly. Defaulting a
      // missing flag to false would quietly empty every tank plan when the app
      // talks to an older backend.
      final product = SprayProduct.fromJson({
        'name': 'Propiconazole 25% EC',
        'category': 'fungicide',
        'dose_per_acre': '200 ml',
        'water_per_acre': '200 L',
      });
      expect(product.droneReady, isTrue);
    });

    test('a seed dressing is kept out of the tank', () {
      final product = SprayProduct.fromJson({
        'name': 'Carboxin + Thiram DS',
        'category': 'fungicide',
        'dose_per_acre': '2.5 g per kg seed',
        'water_per_acre': '--',
        'drone_ready': false,
      });
      expect(product.droneReady, isFalse);
      // No water figure, so the dose line must not invent one.
      expect(product.doseLine, '2.5 g per kg seed per acre');
    });

    test('the dose line reads as a dealer would need it written', () {
      final product = SprayProduct.fromJson({
        'name': 'Thiamethoxam 25% WG',
        'category': 'insecticide',
        'dose_per_acre': '40 g',
        'water_per_acre': '150-200 L',
      });
      expect(product.doseLine, '40 g in 150-200 L of water, per acre');
    });
  });

  group('TankPlan', () {
    test('a plan with only unsprayable findings offers no tank', () {
      final plan = TankPlan.fromJson({
        'passes': [],
        'pass_count': 0,
        'not_sprayable': [
          {
            'condition': 'Fusarium wilt',
            'why': 'Soil-borne.',
            'instead': ['Rotate out of gram'],
          },
        ],
      });
      // This is what gates the spray button: a real diagnosis with no spray
      // behind it must not reach a tank confirmation.
      expect(plan.hasSomethingToSpray, isFalse);
      expect(plan.notSprayable.single.instead, isNotEmpty);
    });

    test('separate tanks are surfaced, not merged', () {
      final plan = TankPlan.fromJson({
        'pass_count': 2,
        'needs_separate_passes': true,
        'passes': [
          {
            'pass': 1,
            'tank_group': 'protectant',
            'tank_name': 'Fungicide / bactericide tank',
            'targets': ['Soybean rust'],
            'load': {'name': 'Hexaconazole 5% EC', 'category': 'fungicide'},
            'alternates': [
              {'name': 'Propiconazole 25% EC', 'category': 'fungicide'},
            ],
          },
          {
            'pass': 2,
            'tank_group': 'insecticide',
            'tank_name': 'Insecticide tank',
            'targets': ['Girdle beetle damage'],
            'load': {'name': 'Thiacloprid 21.7% SC', 'category': 'insecticide'},
            'alternates': [],
          },
        ],
      });
      expect(plan.hasSomethingToSpray, isTrue);
      expect(plan.needsSeparatePasses, isTrue);
      // The alternates are for the *next* spray. Treating them as part of this
      // load is how a tank ends up full of unsprayable sludge.
      expect(plan.passes.first.load!.name, 'Hexaconazole 5% EC');
      expect(plan.passes.first.alternates.single.name, 'Propiconazole 25% EC');
    });
  });

  group('CropHealth', () {
    test('a pass that scanned nothing has no score, not a zero', () {
      final health = CropHealth.fromJson({
        'score': null,
        'band': 'unknown',
        'headline': 'nothing was scanned on this pass',
      });
      // Zero would read as a dead crop; null renders as an em dash.
      expect(health.score, isNull);
      expect(health.needsAction, isFalse);
    });

    test('poor and critical are the bands that call for action', () {
      for (final band in ['poor', 'critical']) {
        expect(
          CropHealth.fromJson({'score': 30, 'band': band}).needsAction,
          isTrue,
          reason: '$band should call for action',
        );
      }
      for (final band in ['good', 'fair']) {
        expect(
          CropHealth.fromJson({'score': 80, 'band': band}).needsAction,
          isFalse,
        );
      }
    });
  });

  group('CameraMode', () {
    test('the wire ids match the backend, including rgb for the IP camera', () {
      expect(CameraMode.fromId('rgb'), CameraMode.ipCamera);
      expect(CameraMode.fromId('multispectral'), CameraMode.multispectral);
      expect(CameraMode.fromId('both'), CameraMode.both);
    });

    test('an unknown mode falls back to the one that works everywhere', () {
      expect(CameraMode.fromId('thermal'), CameraMode.ipCamera);
      expect(CameraMode.fromId(null), CameraMode.ipCamera);
    });

    test('which rig each mode reads', () {
      expect(CameraMode.multispectral.usesRgb, isFalse);
      expect(CameraMode.multispectral.usesBands, isTrue);
      expect(CameraMode.ipCamera.usesRgb, isTrue);
      expect(CameraMode.ipCamera.usesBands, isFalse);
      expect(CameraMode.both.usesRgb, isTrue);
      expect(CameraMode.both.usesBands, isTrue);
    });
  });

  group('SurveyCapabilities', () {
    SurveyCapabilities build({
      required bool rgb,
      required bool bands,
      required bool both,
    }) {
      return SurveyCapabilities.fromJson({
        'camera_modes': [
          {'id': 'rgb', 'name': 'IP camera', 'available': rgb, 'reason': rgb ? '' : 'No RGB camera is registered.'},
          {'id': 'multispectral', 'name': 'Multispectral', 'available': bands},
          {'id': 'both', 'name': 'Both', 'available': both},
        ],
        'advisor': {'available': false, 'message': 'Not configured.'},
        'spray_hardware': {'mechanism': 'sprayer', 'variable_rate': false},
      });
    }

    test('preselects the richest mode the rig can actually fly', () {
      expect(build(rgb: true, bands: true, both: true).defaultMode, CameraMode.both);
      expect(build(rgb: true, bands: false, both: false).defaultMode, CameraMode.ipCamera);
      expect(
        build(rgb: false, bands: true, both: false).defaultMode,
        CameraMode.multispectral,
      );
    });

    test('an unavailable mode carries the reason it cannot be flown', () {
      final option = build(rgb: false, bands: false, both: false)
          .optionFor(CameraMode.ipCamera)!;
      // The reason is the actionable part of the setup screen; a greyed-out
      // control with no explanation tells the operator nothing.
      expect(option.available, isFalse);
      expect(option.reason, contains('No RGB camera'));
    });

    test('a rig with no cameras offers nothing', () {
      expect(build(rgb: false, bands: false, both: false).hasAnyMode, isFalse);
    });
  });

  group('TreatmentMap', () {
    Map<String, dynamic> mapJson({
      required bool georeferenced,
      required int patches,
    }) => {
      'source': 'rgb_detections',
      'prescription_id': 7,
      'index_name': 'CNN detection severity',
      'patch_count': patches,
      'clusters': [
        {'cluster': 0, 'severity': 'severe', 'frames': 8, 'mean_index': 0.9,
         'lat': 23.19, 'lon': 77.42, 'radius_m': 16.5},
        {'cluster': 1, 'severity': 'healthy', 'frames': 8, 'mean_index': 0.02},
      ],
      'options': [
        {'id': 'severe_only', 'label': 'Spray severely affected only',
         'treated_percent': 33, 'saving_percent': 67},
        {'id': 'severe_moderate', 'label': 'Spray severe + moderate',
         'treated_percent': 67, 'saving_percent': 47, 'recommended': true},
        {'id': 'blanket', 'label': 'Spray the whole block',
         'treated_percent': 100, 'saving_percent': 0},
      ],
      'coverage': {'can_georeference': georeferenced, 'assumptions': ['nadir']},
      'notes': [],
    };

    test('the blanket baseline is not offered as a targeted choice', () {
      final map = TreatmentMap.fromJson(mapJson(georeferenced: true, patches: 2));
      expect(map.options.length, 3);
      expect(map.targetedOptions.map((o) => o.id), ['severe_only', 'severe_moderate']);
      expect(map.recommendedOption?.id, 'severe_moderate');
    });

    test('no position data means the map cannot be flown', () {
      final map = TreatmentMap.fromJson(mapJson(georeferenced: false, patches: 2));
      expect(map.isFlyable, isFalse);
    });

    test('no patches means there is nothing to target', () {
      final map = TreatmentMap.fromJson(mapJson(georeferenced: true, patches: 0));
      expect(map.isFlyable, isFalse);
    });

    test('the source is kept, because the two maps are not equal evidence', () {
      final map = TreatmentMap.fromJson(mapJson(georeferenced: true, patches: 2));
      expect(map.source, 'rgb_detections');
    });
  });

  group('SurveySummary', () {
    Map<String, dynamic> summaryJson({
      required bool sprayable,
      required bool flyable,
    }) => {
      'run_id': 3,
      'camera_mode': 'rgb',
      'detection_target': 'both',
      'crop': 'soybean',
      'health': {'score': 52, 'band': 'poor', 'headline': 'a real problem is spreading'},
      'scan': {'status': 'ok', 'frames': 24},
      'tank_plan': {
        'pass_count': sprayable ? 1 : 0,
        'passes': sprayable
            ? [
                {
                  'pass': 1,
                  'tank_group': 'protectant',
                  'load': {'name': 'Hexaconazole 5% EC', 'category': 'fungicide'},
                  'alternates': [],
                  'targets': ['Soybean rust'],
                },
              ]
            : [],
        'not_sprayable': [],
      },
      'prescription': {
        'prescription_id': flyable ? 7 : null,
        'patch_count': flyable ? 2 : 0,
        'clusters': [],
        'options': [],
        'coverage': {'can_georeference': flyable},
      },
      'action_plan': [],
      'treatments': [],
      'advisor': {'available': true},
      'notes': [],
    };

    test('the spray step needs all three: something, somewhere, and a plan', () {
      expect(
        SurveySummary.fromJson(summaryJson(sprayable: true, flyable: true))
            .canOfferSpray,
        isTrue,
      );
      // Nothing worth spraying.
      expect(
        SurveySummary.fromJson(summaryJson(sprayable: false, flyable: true))
            .canOfferSpray,
        isFalse,
      );
      // Nowhere to spray it.
      expect(
        SurveySummary.fromJson(summaryJson(sprayable: true, flyable: false))
            .canOfferSpray,
        isFalse,
      );
    });

    test('an empty scan block is not parsed as a scan of zero frames', () {
      final summary = SurveySummary.fromJson({
        ...summaryJson(sprayable: false, flyable: false),
        'scan': {'status': 'empty', 'frames': 0},
      });
      // Null, so the UI says "nothing was scanned" instead of drawing a row of
      // zeroes that look like measurements.
      expect(summary.scan, isNull);
    });
  });

  group('SurveyProgress', () {
    test('a reconnecting feed is reported as lost, not as the last good frame', () {
      final progress = SurveyProgress.fromJson({
        'running': true,
        'scanned': 12,
        'stream': {'state': 'reconnecting'},
        'latest': {
          'disease': {'name': 'Soybean rust', 'confidence': 0.7},
          'severity': {'level': 'high'},
        },
      });
      expect(progress.signalLost, isTrue);
    });

    test('a frame with no fix cannot become a spray target', () {
      final progress = SurveyProgress.fromJson({
        'running': true,
        'scanned': 3,
        'latest': {'disease': {}, 'weeds': {'weed_coverage': 0.1}},
        'stream': {'state': 'live'},
      });
      expect(progress.hasFix, isFalse);
      expect(progress.latestWeedPercent, 10);
    });

    test('no analysis at all still carries the shot count', () {
      // A multispectral-only run has no analyser, but it does take shots.
      final progress = SurveyProgress.fromJson(null, shots: 4);
      expect(progress.running, isFalse);
      expect(progress.shots, 4);
    });
  });

  group('CropCatalogItem', () {
    test('the weeds tile is distinguishable from a crop', () {
      final weeds = CropCatalogItem.fromJson({
        'id': 'weeds',
        'name': 'Weeds',
        'local_name': 'Kharpatwar / खरपतवार',
        'weed_count': 10,
      });
      expect(weeds.isWeeds, isTrue);
      // The tile shows the Devanagari half, which is what most farmers here
      // will recognise first.
      expect(weeds.shortLocalName, 'खरपतवार');
    });

    test('a crop with no herbicide guidance says so', () {
      final crop = CropCatalogItem.fromJson({
        'id': 'soybean',
        'name': 'Soybean',
        'has_herbicide_guidance': false,
      });
      expect(crop.isWeeds, isFalse);
      expect(crop.hasHerbicideGuidance, isFalse);
    });
  });

  group('ScanMode', () {
    test('the wire ids match the backend scan targets', () {
      expect(ScanMode.fromId('weed'), ScanMode.weed);
      expect(ScanMode.fromId('disease'), ScanMode.disease);
      expect(ScanMode.fromId('both'), ScanMode.both);
      expect(ScanMode.fromId('nonsense'), ScanMode.both);
    });
  });
}
