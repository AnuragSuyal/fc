import 'package:flutter/material.dart';

String? reactionArtworkAsset(String emoji) {
  switch (emoji) {
    case '\u{1F926}':
    case '\u{1F926}\u200D\u2642\uFE0F':
      return 'assets/images/reaction_facepalm.png';
    case '\u{1F610}':
      return 'assets/images/reaction_dark_line.png';
    case '\u{1F60F}':
      return 'assets/images/reaction_smirk.png';
    case '\u{1F64C}':
      return 'assets/images/reaction_raise_hands.png';
    case '\u{1F44B}':
    case '\u{1F44B}\uFE0F':
      return 'assets/images/reaction_wave.png';
    case '\u{1FAF6}':
      return 'assets/images/reaction_like_you.png';
    case '\u{1F3A4}':
      return 'assets/images/reaction_mic.png';
    case '\u{1F4AC}':
      return 'assets/images/reaction_chat.png';
    case '\u{1F534}':
      return 'assets/images/reaction_live.png';
    case '\u{1F442}':
      return 'assets/images/reaction_listen.png';
    case '\u{1F44F}':
      return 'assets/images/reaction_clap.png';
    case '\u{1F3B5}':
      return 'assets/images/reaction_music.png';
    case '\u{1F47B}':
      return 'assets/images/reaction_ghost.png';
    case '\u{1F47D}':
      return 'assets/images/reaction_alien.png';
    case '\u{1F916}':
      return 'assets/images/reaction_robot.png';
    case '\u{1F57A}':
      return 'assets/images/reaction_swing.png';
    case '\u{1F3AE}':
      return 'assets/images/reaction_game.png';
    case '\u{1F92B}':
      return 'assets/images/reaction_shh.png';
    case '\u{2B50}':
      return 'assets/images/reaction_star.png';
    case '\u{1F4A4}':
      return 'assets/images/reaction_afk.png';
    case '\u{1F647}':
      return 'assets/images/reaction_im_wrong.png';
    case '\u{1F618}':
      return 'assets/images/reaction_kiss.png';
    case '\u{1F680}':
      return 'assets/images/reaction_rocket.png';
    case '\u{1F62D}':
      return 'assets/images/reaction_tears_run.png';
    case '\u{1F621}':
      return 'assets/images/reaction_angry.png';
    case '\u{1F622}':
      return 'assets/images/reaction_cried.png';
    case '\u{1F604}':
      return 'assets/images/reaction_grin.png';
    case '\u{1F603}':
      return 'assets/images/reaction_chill.png';
    case '\u{1F634}':
      return 'assets/images/reaction_sleepy.png';
    case '\u{1F62E}':
      return 'assets/images/reaction_oops.png';
    case '\u{2764}':
    case '\u{2764}\uFE0F':
      return 'assets/images/reaction_heart.png';
    default:
      return null;
  }
}

class ReactionArtwork extends StatelessWidget {
  final String emoji;
  final double size;
  final TextStyle? fallbackTextStyle;

  const ReactionArtwork({
    super.key,
    required this.emoji,
    required this.size,
    this.fallbackTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final asset = reactionArtworkAsset(emoji);
    if (asset != null) {
      return Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      );
    }

    return Text(
      emoji,
      style: fallbackTextStyle ??
          TextStyle(
            fontSize: size,
            height: 1,
          ),
    );
  }
}
