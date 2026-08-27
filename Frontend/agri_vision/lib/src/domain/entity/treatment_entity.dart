import 'package:equatable/equatable.dart';

/// What to put in the tank, from `app/ai/treatment_kb.py`.
///
/// The app already showed a farmer what was wrong with their crop and then
/// stopped one question short of the only one that matters. These models carry
/// the answer to it: which product, at what dose, in how much water, and
/// whether the drone can deliver it at all.
///
/// Two distinctions here are load-bearing rather than cosmetic, and the UI is
/// built to keep them visible:
///
///   * [SprayProduct.droneReady] — a seed dressing or a soil drench is not a
///     spray. Showing it in a tank plan would send an aircraft up carrying
///     something that was never going to work.
///   * [Treatment.sprayable] — a virus has no spray that treats it. Its entry
///     targets the *vector* instead, and says so.
class SprayProduct extends Equatable {
  /// Named by active ingredient and formulation, not by brand — that is what
  /// the label says and what a dealer can match.
  final String name;

  /// fungicide | insecticide | herbicide | bactericide | biological | nutrient
  final String category;

  /// Per acre, because that is the unit an operator in MP works in.
  final String dosePerAcre;
  final String waterPerAcre;
  final String timing;
  final String note;

  /// Pre-harvest interval in days, when the label gives one.
  final int? phiDays;

  /// False for anything that is not a spray at all.
  final bool droneReady;

  /// Which products can share a tank: protectant | biological | insecticide |
  /// herbicide.
  final String tankGroup;

  const SprayProduct({
    required this.name,
    required this.category,
    required this.dosePerAcre,
    required this.waterPerAcre,
    required this.timing,
    required this.note,
    required this.phiDays,
    required this.droneReady,
    required this.tankGroup,
  });

  factory SprayProduct.fromJson(Map<String, dynamic> json) {
    return SprayProduct(
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? '',
      dosePerAcre: json['dose_per_acre']?.toString() ?? '',
      waterPerAcre: json['water_per_acre']?.toString() ?? '',
      timing: json['timing']?.toString() ?? '',
      note: json['note']?.toString() ?? '',
      phiDays: json['phi_days'] == null
          ? null
          : int.tryParse('${json['phi_days']}'),
      // Absent means yes: only the entries that are *not* sprays say so
      // explicitly, and defaulting a missing flag to false would quietly
      // empty every tank plan against an older backend.
      droneReady: json['drone_ready'] == null || json['drone_ready'] == true,
      tankGroup: json['tank_group']?.toString() ?? 'protectant',
    );
  }

  /// "40 g in 150–200 L of water, per acre" — the line a dealer needs.
  String get doseLine {
    if (waterPerAcre.isEmpty || waterPerAcre == '--' || waterPerAcre == '—') {
      return '$dosePerAcre per acre';
    }
    return '$dosePerAcre in $waterPerAcre of water, per acre';
  }

  @override
  List<Object?> get props => [name, category, dosePerAcre, droneReady];
}

/// Everything the app knows about treating one condition.
class Treatment extends Equatable {
  final String conditionId;
  final String summary;

  /// False when nothing sprayed will help — a virus, a seed-borne disease, a
  /// soil-borne wilt. The UI must not offer a spray run for these.
  final bool sprayable;

  /// routine | soon | urgent
  final String urgency;

  final List<SprayProduct> products;

  /// What to do that is not a spray. For an unsprayable condition this is the
  /// whole answer, not a footnote.
  final List<String> cultural;

  final String disclaimer;

  const Treatment({
    required this.conditionId,
    required this.summary,
    required this.sprayable,
    required this.urgency,
    required this.products,
    required this.cultural,
    required this.disclaimer,
  });

  static const Treatment empty = Treatment(
    conditionId: '',
    summary: '',
    sprayable: false,
    urgency: 'routine',
    products: [],
    cultural: [],
    disclaimer: '',
  );

  /// Only the products an aircraft can actually deliver.
  List<SprayProduct> get droneProducts =>
      products.where((product) => product.droneReady).toList();

  bool get isEmpty => conditionId.isEmpty && products.isEmpty;

  factory Treatment.fromJson(Map<String, dynamic> json) {
    return Treatment(
      conditionId: json['condition_id']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      sprayable: json['sprayable'] == true,
      urgency: json['urgency']?.toString() ?? 'routine',
      products: _products(json['products']),
      cultural: _strings(json['cultural']),
      disclaimer: json['disclaimer']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [conditionId, sprayable, urgency, products];
}

/// One tank. Products from different groups cannot share a load, so a survey
/// that finds a fungal disease, an insect and heavy weeds produces three of
/// these — and the app says so rather than implying one flight will do.
class TankPass extends Equatable {
  final int pass;
  final String tankGroup;
  final String tankName;

  /// The product that actually goes in this load.
  final SprayProduct? load;

  /// For the *next* spray, to rotate the chemical group. Not for this load.
  final List<SprayProduct> alternates;

  /// The conditions this pass treats.
  final List<String> targets;

  const TankPass({
    required this.pass,
    required this.tankGroup,
    required this.tankName,
    required this.load,
    required this.alternates,
    required this.targets,
  });

  factory TankPass.fromJson(Map<String, dynamic> json) {
    final load = (json['load'] as Map?)?.cast<String, dynamic>();
    return TankPass(
      pass: int.tryParse('${json['pass']}') ?? 1,
      tankGroup: json['tank_group']?.toString() ?? '',
      tankName: json['tank_name']?.toString() ?? '',
      load: load == null ? null : SprayProduct.fromJson(load),
      alternates: _products(json['alternates']),
      targets: _strings(json['targets']),
    );
  }

  @override
  List<Object?> get props => [pass, tankGroup, load, targets];
}

/// A condition the aircraft cannot help with, and what to do instead.
class UnsprayableCondition extends Equatable {
  final String condition;
  final String why;
  final List<String> instead;

  const UnsprayableCondition({
    required this.condition,
    required this.why,
    required this.instead,
  });

  factory UnsprayableCondition.fromJson(Map<String, dynamic> json) {
    return UnsprayableCondition(
      condition: json['condition']?.toString() ?? '',
      why: json['why']?.toString() ?? '',
      instead: _strings(json['instead']),
    );
  }

  @override
  List<Object?> get props => [condition, why];
}

/// Everything a survey found, grouped into tanks.
class TankPlan extends Equatable {
  final List<TankPass> passes;
  final int passCount;
  final bool needsSeparatePasses;
  final List<UnsprayableCondition> notSprayable;
  final String note;
  final String disclaimer;

  const TankPlan({
    required this.passes,
    required this.passCount,
    required this.needsSeparatePasses,
    required this.notSprayable,
    required this.note,
    required this.disclaimer,
  });

  static const TankPlan empty = TankPlan(
    passes: [],
    passCount: 0,
    needsSeparatePasses: false,
    notSprayable: [],
    note: '',
    disclaimer: '',
  );

  /// Whether there is anything at all worth filling a tank for. The spray
  /// authorisation is gated on this, not on "a disease was found" — plenty of
  /// real diagnoses have no spray behind them.
  bool get hasSomethingToSpray => passes.any((pass) => pass.load != null);

  factory TankPlan.fromJson(Map<String, dynamic> json) {
    return TankPlan(
      passes:
          (json['passes'] as List?)
              ?.map((e) => TankPass.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      passCount: int.tryParse('${json['pass_count']}') ?? 0,
      needsSeparatePasses: json['needs_separate_passes'] == true,
      notSprayable:
          (json['not_sprayable'] as List?)
              ?.map((e) =>
                  UnsprayableCondition.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      note: json['note']?.toString() ?? '',
      disclaimer: json['disclaimer']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [passes, passCount, notSprayable];
}

/// The treatment section under a phone scan: the disease half, the weed half,
/// and the tank plan that comes out of both.
class ScanTreatment extends Equatable {
  final Treatment? disease;
  final Treatment? weeds;
  final TankPlan tankPlan;
  final String disclaimer;

  const ScanTreatment({
    required this.disease,
    required this.weeds,
    required this.tankPlan,
    required this.disclaimer,
  });

  factory ScanTreatment.fromJson(Map<String, dynamic> json) {
    final disease = (json['disease'] as Map?)?.cast<String, dynamic>();
    final weeds = (json['weeds'] as Map?)?.cast<String, dynamic>();
    final plan = (json['tank_plan'] as Map?)?.cast<String, dynamic>();
    return ScanTreatment(
      disease: disease == null ? null : Treatment.fromJson(disease),
      weeds: weeds == null ? null : Treatment.fromJson(weeds),
      tankPlan: plan == null ? TankPlan.empty : TankPlan.fromJson(plan),
      disclaimer: json['disclaimer']?.toString() ?? '',
    );
  }

  @override
  List<Object?> get props => [disease, weeds, tankPlan];
}

// ── shared parsing ───────────────────────────────────────────────────────────

List<SprayProduct> _products(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((e) => SprayProduct.fromJson(Map<String, dynamic>.from(e)))
      .toList();
}

List<String> _strings(dynamic raw) {
  if (raw is! List) return const [];
  return raw.map((e) => '$e').where((e) => e.isNotEmpty).toList();
}
