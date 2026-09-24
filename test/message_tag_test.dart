// The tag colours are the whole feature: if two tags render the same, the
// three buttons are decoration. These check the mapping holds in BOTH palettes,
// since a tone that separates on navy can collapse on white.


import 'package:flutter_test/flutter_test.dart';
import 'package:ledgiproof/services/workspace_chat_service.dart';
import 'package:ledgiproof/theme/app_theme.dart';
import 'package:ledgiproof/widgets/message_tag_style.dart';

void main() {
  test('tag strings round-trip through the values the CHECK allows', () {
    for (final t in MessageTag.values) {
      expect(
        const {'normal', 'pending', 'invoice', 'urgent'},
        contains(messageTagTo(t)),
        reason: '$t must serialise to a value workspace_messages accepts',
      );
    }
    // Every allowed value is reachable, so the enum and the constraint cannot
    // drift apart in either direction.
    expect(MessageTag.values.map(messageTagTo).toSet(),
        {'normal', 'pending', 'invoice', 'urgent'});
  });

  test('normal is the default, so three buttons cover the rest', () {
    expect(MessageTag.values.length, 4);
    expect(MessageTag.values.first, MessageTag.normal);
  });

  test('every tag is a different colour, in light and in dark', () {
    for (final palette in <LpPalette>[LpPalette.dark, LpPalette.light]) {
      AppColors.use(palette);
      final inks = <int>{};
      final backgrounds = <int>{};
      for (final t in MessageTag.values) {
        final c = tagColours(t);
        inks.add(c.ink.toARGB32());
        backgrounds.add(c.bg.toARGB32());
      }
      expect(inks.length, MessageTag.values.length,
          reason: 'two tags share an ink colour in ${palette.brightness}');
      expect(backgrounds.length, MessageTag.values.length,
          reason: 'two tags share a background in ${palette.brightness}');
    }
    AppColors.use(LpPalette.dark);
  });
}
