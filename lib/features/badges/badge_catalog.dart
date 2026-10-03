import 'badge_models.dart';

part 'data/badge_launch_catalog.dart';

abstract final class BadgeCatalog {
  static const repTargets = [25, 100, 250, 500, 1000, 5000];
  static const timedMinuteTargets = [5, 15, 30, 60, 180, 500];
  static const ladderTiers = [
    BadgeTier.bronze,
    BadgeTier.silver,
    BadgeTier.gold,
    BadgeTier.platinum,
    BadgeTier.blackBelt,
    BadgeTier.legend,
  ];

  static final launchBadges = _badgeLaunchCatalog;

  static BadgeDefinition byId(String id) {
    return launchBadges.firstWhere((badge) => badge.id == id);
  }

  static List<BadgeDefinition> _repLadder({
    required String calloutId,
    required String iconName,
    required List<String> titles,
    required String noun,
  }) {
    return [
      for (var i = 0; i < repTargets.length; i++)
        _badge(
          id: '${calloutId}_${repTargets[i]}',
          title: titles[i],
          description: 'Complete ${_fmt(repTargets[i])} $noun.',
          category: BadgeCategory.moveMastery,
          tier: ladderTiers[i],
          target: repTargets[i],
          metricKey: 'callout.$calloutId',
          iconName: iconName,
        ),
    ];
  }

  static List<BadgeDefinition> _timedLadder({
    required String calloutId,
    required String iconName,
    required List<String> titles,
    required String noun,
  }) {
    return [
      for (var i = 0; i < timedMinuteTargets.length; i++)
        _badge(
          id: '${calloutId}_${timedMinuteTargets[i]}m',
          title: titles[i],
          description: 'Complete ${timedMinuteTargets[i]} total minutes $noun.',
          category: BadgeCategory.timedMastery,
          tier: ladderTiers[i],
          target: timedMinuteTargets[i],
          metricKey: 'timed.$calloutId.minutes',
          iconName: iconName,
        ),
    ];
  }

  static List<BadgeDefinition> _streakBadges() {
    const data = [
      ('first_snap', 'First Snap', 1, BadgeTier.bronze),
      ('back_tomorrow', 'Back Tomorrow', 2, BadgeTier.bronze),
      ('three_day_scrapper', '3-Day Scrapper', 3, BadgeTier.silver),
      ('one_week_warrior', 'One Week Warrior', 7, BadgeTier.gold),
      ('two_week_grind', 'Two Week Grind', 14, BadgeTier.platinum),
      ('built_different', 'Built Different', 30, BadgeTier.blackBelt),
      ('season_discipline', 'Season Discipline', 60, BadgeTier.blackBelt),
      ('no_days_off', 'No Days Off', 100, BadgeTier.legend),
    ];

    return [
      for (final item in data)
        _badge(
          id: 'streak_${item.$1}',
          title: item.$2,
          description: item.$3 == 1
              ? 'Complete your first workout.'
              : 'Complete workouts ${item.$3} days in a row.',
          category: BadgeCategory.streak,
          tier: item.$4,
          target: item.$3,
          metricKey: 'streak.days',
          iconName: 'streak',
        ),
    ];
  }

  static List<BadgeDefinition> _socialBadges() {
    return const [
      BadgeDefinition(
        id: 'social_first_share',
        title: 'Pass the Torch',
        description: 'Send your first workout to a teammate.',
        category: BadgeCategory.social,
        tier: BadgeTier.bronze,
        targetProgress: 1,
        metricKey: 'social.shared_workouts',
        iconName: 'social',
      ),
      BadgeDefinition(
        id: 'social_first_relay',
        title: 'Relay Started',
        description: 'Have a teammate accept or complete your workout.',
        category: BadgeCategory.social,
        tier: BadgeTier.bronze,
        targetProgress: 1,
        metricKey: 'social.qualified_relays',
        iconName: 'social',
      ),
      BadgeDefinition(
        id: 'social_relay_3',
        title: 'Three-Day Relay',
        description: 'Qualify a Relay Streak on 3 consecutive days.',
        category: BadgeCategory.social,
        tier: BadgeTier.silver,
        targetProgress: 3,
        metricKey: 'social.relay_streak',
        iconName: 'relay',
      ),
      BadgeDefinition(
        id: 'social_relay_7',
        title: 'Torch Bearer',
        description: 'Qualify a Relay Streak on 7 consecutive days.',
        category: BadgeCategory.social,
        tier: BadgeTier.gold,
        targetProgress: 7,
        metricKey: 'social.relay_streak',
        iconName: 'relay',
      ),
      BadgeDefinition(
        id: 'social_friend_finisher',
        title: 'Answered the Call',
        description: 'Complete your first received team workout.',
        category: BadgeCategory.social,
        tier: BadgeTier.bronze,
        targetProgress: 1,
        metricKey: 'social.completed_friend_workouts',
        iconName: 'friend_workout',
      ),
      BadgeDefinition(
        id: 'social_friend_streak_3',
        title: 'Team Workout Three',
        description: 'Complete team workouts on 3 consecutive days.',
        category: BadgeCategory.social,
        tier: BadgeTier.silver,
        targetProgress: 3,
        metricKey: 'social.friend_streak',
        iconName: 'friend_workout',
      ),
      BadgeDefinition(
        id: 'social_friend_streak_7',
        title: 'Never Leave Them Hanging',
        description: 'Complete team workouts on 7 consecutive days.',
        category: BadgeCategory.social,
        tier: BadgeTier.gold,
        targetProgress: 7,
        metricKey: 'social.friend_streak',
        iconName: 'friend_workout',
      ),
      BadgeDefinition(
        id: 'social_partner_2',
        title: 'Tag Team',
        description: 'Both partners complete shared workouts for 2 weeks.',
        category: BadgeCategory.social,
        tier: BadgeTier.silver,
        targetProgress: 2,
        metricKey: 'social.partner_streak',
        iconName: 'partner',
      ),
      BadgeDefinition(
        id: 'social_partner_5',
        title: 'Iron Sharpens Iron',
        description: 'Both partners complete shared workouts for 5 weeks.',
        category: BadgeCategory.social,
        tier: BadgeTier.platinum,
        targetProgress: 5,
        metricKey: 'social.partner_streak',
        iconName: 'partner',
      ),
      BadgeDefinition(
        id: 'social_crew_1',
        title: 'Crew Assembled',
        description: 'Have 3 teammates complete the same workout.',
        category: BadgeCategory.social,
        tier: BadgeTier.silver,
        targetProgress: 1,
        metricKey: 'social.crew_weeks',
        iconName: 'crew',
      ),
      BadgeDefinition(
        id: 'social_crew_3',
        title: 'Crew on a Roll',
        description: 'Qualify a Crew Streak for 3 consecutive weeks.',
        category: BadgeCategory.social,
        tier: BadgeTier.gold,
        targetProgress: 3,
        metricKey: 'social.crew_streak',
        iconName: 'crew',
      ),
      BadgeDefinition(
        id: 'social_century',
        title: 'Social Century',
        description: 'Earn 100 server-verified social progress points.',
        category: BadgeCategory.social,
        tier: BadgeTier.gold,
        targetProgress: 100,
        metricKey: 'social.points',
        iconName: 'social',
      ),
    ];
  }

  static List<BadgeDefinition> _grindBadges() {
    const workoutData = [
      ('first_drill', 'First Drill', 1, BadgeTier.bronze),
      ('ten_toes_down', 'Ten Toes Down', 10, BadgeTier.bronze),
      ('mat_rat', 'Mat Rat', 25, BadgeTier.silver),
      ('practice_room_regular', 'Practice Room Regular', 50, BadgeTier.gold),
      ('basement_grinder', 'Basement Grinder', 100, BadgeTier.platinum),
      ('everyday_wrestler', 'Everyday Wrestler', 250, BadgeTier.blackBelt),
      ('legendary_worker', 'Legendary Worker', 500, BadgeTier.legend),
    ];
    const minuteData = [
      ('first_minute', 'First Minute', 1, BadgeTier.bronze),
      ('one_hour_worker', 'One-Hour Worker', 60, BadgeTier.silver),
      ('five_hour_grinder', 'Five-Hour Grinder', 300, BadgeTier.gold),
      ('ten_hour_tough_guy', 'Ten-Hour Tough Guy', 600, BadgeTier.platinum),
      ('hundred_hour_legend', 'Hundred-Hour Legend', 6000, BadgeTier.legend),
    ];

    return [
      for (final item in workoutData)
        _badge(
          id: 'grind_${item.$1}',
          title: item.$2,
          description: 'Complete ${_fmt(item.$3)} workout'
              '${item.$3 == 1 ? '' : 's'}.',
          category: BadgeCategory.grind,
          tier: item.$4,
          target: item.$3,
          metricKey: 'workouts.total',
          iconName: 'grind',
        ),
      for (final item in minuteData)
        _badge(
          id: 'grind_${item.$1}',
          title: item.$2,
          description: item.$3 == 1
              ? 'Complete 1 total training minute.'
              : 'Complete ${_fmt(item.$3)} total training minutes.',
          category: BadgeCategory.grind,
          tier: item.$4,
          target: item.$3,
          metricKey: 'training.minutes',
          iconName: 'timer',
        ),
    ];
  }

  static List<BadgeDefinition> _difficultyBadges() {
    return [
      _badge(
        id: 'difficulty_turn_it_up',
        title: 'Turn It Up',
        description: 'Complete a workout on difficulty 5 or higher.',
        category: BadgeCategory.grind,
        tier: BadgeTier.bronze,
        target: 1,
        metricKey: 'difficulty.5.single',
        iconName: 'difficulty',
      ),
      _badge(
        id: 'difficulty_no_breather',
        title: 'No Breather',
        description: 'Complete a workout on difficulty 8 or higher.',
        category: BadgeCategory.grind,
        tier: BadgeTier.silver,
        target: 1,
        metricKey: 'difficulty.8.single',
        iconName: 'difficulty',
      ),
      _badge(
        id: 'difficulty_chaos_drill',
        title: 'Chaos Drill',
        description: 'Complete a workout on difficulty 10.',
        category: BadgeCategory.grind,
        tier: BadgeTier.gold,
        target: 1,
        metricKey: 'difficulty.10.single',
        iconName: 'difficulty',
      ),
      _badge(
        id: 'difficulty_hard_mode_habit',
        title: 'Hard Mode Habit',
        description: 'Complete 10 workouts on difficulty 8 or higher.',
        category: BadgeCategory.grind,
        tier: BadgeTier.platinum,
        target: 10,
        metricKey: 'difficulty.8.count',
        iconName: 'difficulty',
      ),
      _badge(
        id: 'difficulty_built_for_overtime',
        title: 'Built for Overtime',
        description: 'Complete 25 workouts on difficulty 8 or higher.',
        category: BadgeCategory.grind,
        tier: BadgeTier.blackBelt,
        target: 25,
        metricKey: 'difficulty.8.count',
        iconName: 'difficulty',
      ),
    ];
  }

  static List<BadgeDefinition> _overtimeBadges() {
    return [
      _badge(
        id: 'overtime_bonus',
        title: 'Overtime Bonus',
        description: 'Complete any overtime workout.',
        category: BadgeCategory.flex,
        tier: BadgeTier.bronze,
        target: 1,
        metricKey: 'overtime.workouts',
        iconName: 'overtime',
      ),
      _badge(
        id: 'overtime_sudden_victory_badge',
        title: 'Sudden Victory Badge',
        description: 'Complete 5 overtime workouts.',
        category: BadgeCategory.flex,
        tier: BadgeTier.silver,
        target: 5,
        metricKey: 'overtime.workouts',
        iconName: 'overtime',
      ),
      _badge(
        id: 'overtime_refused_to_quit',
        title: 'Refused to Quit',
        description: 'Complete overtime after a workout 3 days in a row.',
        category: BadgeCategory.flex,
        tier: BadgeTier.gold,
        target: 3,
        metricKey: 'overtime.streak_days',
        iconName: 'overtime',
      ),
      _badge(
        id: 'overtime_state_finals_gas_tank',
        title: 'State Finals Gas Tank',
        description: 'Complete State Champ Overtime.',
        category: BadgeCategory.flex,
        tier: BadgeTier.blackBelt,
        target: 1,
        metricKey: 'overtime.state_champ',
        iconName: 'overtime',
      ),
      _badge(
        id: 'overtime_one_more_period',
        title: 'One More Period',
        description: 'Complete overtime after a 10+ minute workout.',
        category: BadgeCategory.flex,
        tier: BadgeTier.platinum,
        target: 1,
        metricKey: 'overtime.after_10_min',
        iconName: 'overtime',
      ),
    ];
  }

  static List<BadgeDefinition> _comboBadges() {
    const combos = [
      (
        'complete_wrestler',
        'Complete Wrestler',
        'Complete a workout with shot, sprawl, stance, fake, and circle enabled.'
      ),
      (
        'offense_defense',
        'Offense + Defense',
        'Complete a workout with at least 10 shots and 10 sprawls.'
      ),
      (
        'motion_creates_attacks',
        'Motion Creates Attacks',
        'Complete a workout with fakes, level changes, and shots.'
      ),
      (
        'defense_first',
        'Defense First',
        'Complete a workout with sprawls, down blocks, and circles.'
      ),
      (
        'heavy_hands_session',
        'Heavy Hands Session',
        'Complete a workout with snap downs and handfight time.'
      ),
      (
        'gas_tank_session',
        'Gas Tank Session',
        'Complete a workout with high knees, foot fire, and stance.'
      ),
    ];

    return [
      for (final item in combos)
        _badge(
          id: 'combo_${item.$1}',
          title: item.$2,
          description: item.$3,
          category: BadgeCategory.combo,
          tier: BadgeTier.gold,
          target: 1,
          metricKey: 'combo.${item.$1}',
          iconName: 'combo',
        ),
    ];
  }

  static List<BadgeDefinition> _seasonBadges() {
    return [
      _badge(
        id: 'season_preseason_started',
        title: 'Preseason Started',
        description: 'Set a tournament or season target date.',
        category: BadgeCategory.season,
        tier: BadgeTier.bronze,
        target: 1,
        metricKey: 'season.target_set',
        iconName: 'season',
      ),
      _badge(
        id: 'season_on_the_clock',
        title: 'On the Clock',
        description: 'Complete your first workout after setting a target date.',
        category: BadgeCategory.season,
        tier: BadgeTier.silver,
        target: 1,
        metricKey: 'season.on_clock',
        iconName: 'season',
      ),
      _badge(
        id: 'season_on_pace',
        title: 'On Pace',
        description: 'Stay on pace toward your season goal for 3 days.',
        category: BadgeCategory.season,
        tier: BadgeTier.gold,
        target: 3,
        metricKey: 'season.on_pace',
        iconName: 'season',
      ),
      _badge(
        id: 'season_ahead_of_pace',
        title: 'Ahead of Pace',
        description: 'Get 10% ahead of your season goal pace.',
        category: BadgeCategory.season,
        tier: BadgeTier.platinum,
        target: 1,
        metricKey: 'season.ahead_pace',
        iconName: 'season',
      ),
      _badge(
        id: 'season_final_week_grinder',
        title: 'Final Week Grinder',
        description:
            'Complete 5 workouts during the final 7 days before your target date.',
        category: BadgeCategory.season,
        tier: BadgeTier.blackBelt,
        target: 5,
        metricKey: 'season.final_week_workouts',
        iconName: 'season',
      ),
      _badge(
        id: 'season_state_ready',
        title: 'State Ready',
        description: 'Reach your season rep goal before the target date.',
        category: BadgeCategory.season,
        tier: BadgeTier.legend,
        target: 1,
        metricKey: 'season.state_ready',
        iconName: 'season',
      ),
    ];
  }

  static List<BadgeDefinition> _secretBadges() {
    return [
      _secret(
        id: 'still_showed_up',
        title: 'Still Showed Up',
        description: 'Complete a 1-minute workout after missing yesterday.',
        hint: 'Show up even when it is small.',
        metricKey: 'secret.still_showed_up',
      ),
      _secret(
        id: 'comeback_kid',
        title: 'Comeback Kid',
        description: 'Restart a streak after missing 3 or more days.',
        hint: 'Start again after falling off.',
        metricKey: 'secret.comeback_kid',
      ),
      _secret(
        id: 'couldve_quit',
        title: "Could've Quit",
        description: 'Complete a workout after pausing once.',
        hint: 'Finish after a pause.',
        metricKey: 'secret.couldve_quit',
      ),
      _secret(
        id: 'no_pause_monster',
        title: 'No Pause Monster',
        description: 'Complete 10 workouts without pausing.',
        hint: 'Go whistle to whistle.',
        target: 10,
        metricKey: 'secret.no_pause_monster',
      ),
      _secret(
        id: 'just_one_more',
        title: 'Just One More',
        description:
            'Start a second workout within 10 minutes of finishing one.',
        hint: 'One workout was not enough.',
        metricKey: 'secret.just_one_more',
      ),
      _secret(
        id: 'double_session',
        title: 'Double Session',
        description: 'Complete two workouts in one day.',
        hint: 'Train twice in one day.',
        target: 2,
        metricKey: 'secret.workouts_today',
      ),
      _secret(
        id: 'triple_threat',
        title: 'Triple Threat',
        description: 'Complete three workouts in one day.',
        hint: 'Three sessions. One day.',
        target: 3,
        metricKey: 'secret.workouts_today',
      ),
      _secret(
        id: 'the_hard_way',
        title: 'The Hard Way',
        description: 'Complete a 15-minute workout on difficulty 10.',
        hint: 'Max time. Max difficulty.',
        metricKey: 'secret.the_hard_way',
      ),
      _secret(
        id: 'short_but_sharp',
        title: 'Short but Sharp',
        description: 'Complete five 1-minute workouts in one week.',
        hint: 'Small workouts still count.',
        target: 5,
        metricKey: 'secret.one_minute_week',
      ),
      _secret(
        id: 'empty_the_tank',
        title: 'Empty the Tank',
        description:
            'Complete high knees or foot fire for 60 seconds at difficulty 8 or higher.',
        hint: 'Burn through a full conditioning callout.',
        metricKey: 'secret.empty_the_tank',
      ),
    ];
  }

  static List<BadgeDefinition> _premiumBadges() {
    return [
      _premium(
        id: 'custom_coach',
        title: 'Custom Coach',
        description: 'Create your first custom callout.',
        target: 1,
        metricKey: 'premium.custom_callouts',
      ),
      _premium(
        id: 'voice_of_the_room',
        title: 'Voice of the Room',
        description: 'Record 5 custom callouts.',
        target: 5,
        metricKey: 'premium.custom_callouts',
      ),
      _premium(
        id: 'built_my_drill',
        title: 'Built My Drill',
        description: 'Complete a workout using a custom playlist.',
        target: 1,
        metricKey: 'premium.custom_workouts',
      ),
      _premium(
        id: 'my_own_coach',
        title: 'My Own Coach',
        description: 'Complete 10 workouts with custom callouts.',
        target: 10,
        metricKey: 'premium.custom_workouts',
      ),
      _premium(
        id: 'no_watermark_club',
        title: 'No Watermark Club',
        description: 'Save your first premium recording.',
        target: 1,
        metricKey: 'premium.recording_saves',
      ),
      _premium(
        id: 'season_pass_activated',
        title: 'Season Pass Activated',
        description: 'Start your first workout with Season Pass.',
        target: 1,
        metricKey: 'premium.season_pass_workouts',
      ),
      _premium(
        id: 'tournament_prep_mode',
        title: 'Tournament Prep Mode',
        description: 'Complete 5 workouts during a 2-week pass.',
        target: 5,
        metricKey: 'premium.season_pass_workouts',
      ),
      _premium(
        id: 'full_season_grinder',
        title: 'Full Season Grinder',
        description: 'Complete 30 workouts during a Season Pass.',
        target: 30,
        metricKey: 'premium.season_pass_workouts',
      ),
    ];
  }

  static BadgeDefinition _secret({
    required String id,
    required String title,
    required String description,
    required String hint,
    required String metricKey,
    int target = 1,
  }) {
    return _badge(
      id: 'secret_$id',
      title: title,
      description: description,
      category: BadgeCategory.secret,
      tier: BadgeTier.legend,
      target: target,
      metricKey: metricKey,
      iconName: 'secret',
      isSecret: true,
      hint: hint,
    );
  }

  static BadgeDefinition _premium({
    required String id,
    required String title,
    required String description,
    required int target,
    required String metricKey,
  }) {
    return _badge(
      id: 'premium_$id',
      title: title,
      description: description,
      category: BadgeCategory.premium,
      tier: BadgeTier.gold,
      target: target,
      metricKey: metricKey,
      iconName: 'premium',
      isPremium: true,
    );
  }

  static BadgeDefinition _badge({
    required String id,
    required String title,
    required String description,
    required BadgeCategory category,
    required BadgeTier tier,
    required int target,
    required String metricKey,
    required String iconName,
    bool isSecret = false,
    String? hint,
    bool isPremium = false,
  }) {
    return BadgeDefinition(
      id: id,
      title: title,
      description: description,
      category: category,
      tier: tier,
      targetProgress: target,
      metricKey: metricKey,
      iconName: iconName,
      isSecret: isSecret,
      hint: hint,
      isPremium: isPremium,
    );
  }

  static String _fmt(int value) {
    final raw = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < raw.length; i++) {
      final remaining = raw.length - i;
      buffer.write(raw[i]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}
