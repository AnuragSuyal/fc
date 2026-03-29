import 'color_clash_model_utils.dart';

class ColorClashCardModel {
  const ColorClashCardModel({
    required this.id,
    required this.kind,
    this.hue,
    this.value,
  });

  final String id;
  final String kind;
  final String? hue;
  final int? value;

  factory ColorClashCardModel.fromJson(Map<String, dynamic> json) {
    return ColorClashCardModel(
      id: json['id']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      hue: json['hue']?.toString(),
      value: json['value'] == null ? null : asInt(json['value']),
    );
  }

  bool get isNumberCard => kind == 'number';

  bool get requiresHueChoice =>
      kind == 'prism' || kind == 'prism_surge' || kind == 'echo';

  bool get requiresTargetChoice => kind == 'swap' || kind == 'echo';

  bool get isPrismFamily => kind == 'prism' || kind == 'prism_surge';

  bool get isActionCard => !isNumberCard;

  String get hueLabel {
    switch (hue) {
      case 'ember':
        return 'Ember';
      case 'tide':
      case 'tidal':
        return 'Tide';
      case 'grove':
        return 'Grove';
      case 'solar':
        return 'Solar';
      default:
        return 'Prism';
    }
  }

  String get displayName {
    if (isNumberCard) {
      return 'Number ${value ?? ''}'.trim();
    }
    switch (kind) {
      case 'freeze':
        return 'Freeze';
      case 'flip_flow':
        return 'Flip Flow';
      case 'pulse_plus_two':
        return 'Pulse +2';
      case 'prism':
        return 'Prism';
      case 'prism_surge':
        return 'Prism Surge';
      case 'shield':
        return 'Shield';
      case 'echo':
        return 'Echo';
      case 'swap':
        return 'Swap';
      default:
        return kind.replaceAll('_', ' ');
    }
  }

  String get shortLabel {
    if (isNumberCard) {
      return '${value ?? ''}';
    }
    switch (kind) {
      case 'freeze':
        return 'Freeze';
      case 'flip_flow':
        return 'Flip';
      case 'pulse_plus_two':
        return '+2';
      case 'prism':
        return 'Prism';
      case 'prism_surge':
        return 'Surge';
      case 'shield':
        return 'Shield';
      case 'echo':
        return 'Echo';
      case 'swap':
        return 'Swap';
      default:
        return kind;
    }
  }

  String get iconLabel {
    if (isNumberCard) {
      return '${value ?? ''}';
    }
    switch (kind) {
      case 'freeze':
        return 'F';
      case 'flip_flow':
        return '↺';
      case 'pulse_plus_two':
        return '+2';
      case 'prism':
        return 'P';
      case 'prism_surge':
        return 'PS';
      case 'shield':
        return 'S';
      case 'echo':
        return 'E';
      case 'swap':
        return '⇄';
      default:
        return shortLabel;
    }
  }
}

class ColorClashLegalMoveModel {
  const ColorClashLegalMoveModel({
    required this.type,
    this.cardId,
    this.chosenHue,
    this.targetSeat,
  });

  final String type;
  final String? cardId;
  final String? chosenHue;
  final int? targetSeat;

  factory ColorClashLegalMoveModel.fromJson(Map<String, dynamic> json) {
    return ColorClashLegalMoveModel(
      type: json['type']?.toString() ?? '',
      cardId: json['cardId']?.toString(),
      chosenHue: json['chosenHue']?.toString(),
      targetSeat: json['targetSeat'] == null ? null : asInt(json['targetSeat']),
    );
  }

  bool matchesCard(String cardId) => this.cardId == cardId;

  bool get isCardPlay => type == 'play_card' && (cardId ?? '').isNotEmpty;
}

class ColorClashPromptModel {
  const ColorClashPromptModel({
    required this.kind,
    this.sourceSeat,
    this.amount,
  });

  final String kind;
  final int? sourceSeat;
  final int? amount;

  factory ColorClashPromptModel.fromJson(Map<String, dynamic> json) {
    return ColorClashPromptModel(
      kind: json['kind']?.toString() ?? '',
      sourceSeat: json['sourceSeat'] == null ? null : asInt(json['sourceSeat']),
      amount: json['amount'] == null ? null : asInt(json['amount']),
    );
  }

  bool get isChallengeResponse => kind == 'challenge_response';

  String get displayLabel {
    switch (kind) {
      case 'challenge_response':
        return 'Prism Surge check';
      default:
        return kind.replaceAll('_', ' ');
    }
  }
}
