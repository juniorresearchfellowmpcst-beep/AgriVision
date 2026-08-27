import 'package:equatable/equatable.dart';

import 'field_scan_result.dart';
import 'treatment_entity.dart';

/// What a phone scan is asked to look for.
enum ScanMode {
  disease('disease', 'Disease'),
  weed('weed', 'Weeds'),
  both('both', 'Both');

  const ScanMode(this.id, this.label);

  final String id;
  final String label;

  static ScanMode fromId(String? id) {
    for (final mode in ScanMode.values) {
      if (mode.id == id) return mode;
    }
    return ScanMode.both;
  }
}

/// One tile in the crop picker.
///
/// The Weeds tile sits in the same grid as the crops, because that is where a
/// farmer looks for it — but [isWeeds] keeps it distinguishable, so nothing
/// iterating crops to run a disease model is ever handed a non-crop.
class CropCatalogItem extends Equatable {
  final String id;
  final String name;

  /// The Hindi / local name, which is what most farmers will recognise first.
  final String localName;

  /// kharif | rabi | all
  final String season;
  final String note;

  final int diseaseCount;
  final int weedCount;

  /// Whether this crop has registered herbicide guidance. Without it the weed
  /// scan can measure pressure but cannot recommend a product — the same
  /// herbicide that clears wheat kills soybean.
  final bool hasHerbicideGuidance;

  /// Whether the crop is in the ground right now, when the server was asked
  /// with a month. Null when it was not.
  final bool? inSeason;

  const CropCatalogItem({
    required this.id,
    required this.name,
    required this.localName,
    required this.season,
    required this.note,
    required this.diseaseCount,
    required this.weedCount,
    required this.hasHerbicideGuidance,
    required this.inSeason,
  });

  bool get isWeeds => id == 'weeds';

  /// The Devanagari half of "Soyabean / सोयाबीन", when there is one — the
  /// tile shows it under the English name.
  String get shortLocalName {
    if (localName.isEmpty) return '';
    final parts = localName.split('/');
    return parts.length > 1 ? parts.last.trim() : localName.trim();
  }

  factory CropCatalogItem.fromJson(Map<String, dynamic> json) {
    return CropCatalogItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      localName: json['local_name']?.toString() ?? '',
      season: json['season']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      diseaseCount: int.tryParse('${json['disease_count']}') ?? 0,
      weedCount: int.tryParse('${json['weed_count']}') ?? 0,
      hasHerbicideGuidance: json['has_herbicide_guidance'] == true,
      inSeason: json['in_season'] == null ? null : json['in_season'] == true,
    );
  }

  @override
  List<Object?> get props => [id, name, inSeason];
}

/// One disease in one crop, with what to spray for it.
class CropDisease extends Equatable {
  final String id;
  final String name;
  final String pathogen;
  final List<String> symptoms;

  /// The weather and conditions that bring it on — often the most actionable
  /// line on the screen, because it says whether to expect it next week.
  final String favours;
  final List<String> management;
  final String severityNote;

  final Treatment treatment;
  final bool sprayable;

  /// routine | soon | urgent
  final String urgency;

  const CropDisease({
    required this.id,
    required this.name,
    required this.pathogen,
    required this.symptoms,
    required this.favours,
    required this.management,
    required this.severityNote,
    required this.treatment,
    required this.sprayable,
    required this.urgency,
  });

  factory CropDisease.fromJson(Map<String, dynamic> json) {
    final treatment = (json['treatment'] as Map?)?.cast<String, dynamic>();
    return CropDisease(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      pathogen: json['pathogen']?.toString() ?? '',
      symptoms: _strings(json['symptoms']),
      favours: json['favours']?.toString() ?? '',
      management: _strings(json['management']),
      severityNote: json['severity_note']?.toString() ?? '',
      treatment:
          treatment == null ? Treatment.empty : Treatment.fromJson(treatment),
      sprayable: json['sprayable'] == true,
      urgency: json['urgency']?.toString() ?? 'routine',
    );
  }

  @override
  List<Object?> get props => [id, name, urgency];
}

/// One weed, and how to tell it from the crop.
class WeedEntry extends Equatable {
  final String id;
  final String name;
  final String localName;

  /// grass | sedge | broadleaf
  final String type;
  final String note;

  /// How to recognise it — the part that matters standing in a field, because
  /// several of these look almost exactly like a young crop.
  final List<String> identify;
  final List<String> control;

  const WeedEntry({
    required this.id,
    required this.name,
    required this.localName,
    required this.type,
    required this.note,
    required this.identify,
    required this.control,
  });

  factory WeedEntry.fromJson(Map<String, dynamic> json) {
    return WeedEntry(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      localName: json['local_name']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      note: json['why_it_matters']?.toString() ?? json['note']?.toString() ?? '',
      identify: _strings(json['identify']),
      control: _strings(json['control']),
    );
  }

  @override
  List<Object?> get props => [id, name, type];
}

/// One crop opened from the picker: every disease it gets here, its usual
/// weeds, and the herbicides registered for it.
class CropDetail extends Equatable {
  final String id;
  final String name;
  final String localName;
  final String season;
  final String note;
  final List<CropDisease> diseases;
  final List<WeedEntry> weeds;
  final List<SprayProduct> herbicides;
  final String disclaimer;

  const CropDetail({
    required this.id,
    required this.name,
    required this.localName,
    required this.season,
    required this.note,
    required this.diseases,
    required this.weeds,
    required this.herbicides,
    required this.disclaimer,
  });

  factory CropDetail.fromJson(Map<String, dynamic> json) {
    final crop = (json['crop'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CropDetail(
      id: crop['id']?.toString() ?? 'weeds',
      name: crop['name']?.toString() ?? 'Weeds',
      localName: crop['local_name']?.toString() ?? '',
      season: crop['season']?.toString() ?? '',
      note: crop['note']?.toString() ?? '',
      diseases:
          (json['diseases'] as List?)
              ?.map((e) => CropDisease.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      weeds:
          (json['weeds'] as List?)
              ?.map((e) => WeedEntry.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      herbicides:
          (json['herbicides'] as List?)
              ?.map((e) => SprayProduct.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      disclaimer: json['disclaimer']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [id, diseases, weeds];
}

/// A phone scan's result: the ordinary field-scan verdict plus the treatment.
class CropScanResult extends Equatable {
  final FieldScanResult scan;
  final ScanMode mode;
  final ScanTreatment treatment;

  /// Why this cannot become a spray run. Said plainly, because the screen
  /// before it was a drone flow and the difference is not obvious.
  final String sprayNote;
  final bool advisorAvailable;

  const CropScanResult({
    required this.scan,
    required this.mode,
    required this.treatment,
    required this.sprayNote,
    required this.advisorAvailable,
  });

  factory CropScanResult.fromJson(Map<String, dynamic> json) {
    final advisor = (json['advisor'] as Map?)?.cast<String, dynamic>() ?? const {};
    return CropScanResult(
      scan: FieldScanResult.fromJson(json),
      mode: ScanMode.fromId(json['mode']?.toString()),
      treatment: ScanTreatment.fromJson(
        (json['treatment'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      sprayNote: json['spray_note']?.toString() ?? '',
      advisorAvailable: advisor['available'] == true,
    );
  }

  @override
  List<Object?> get props => [scan, mode, treatment];
}

List<String> _strings(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList();
}
