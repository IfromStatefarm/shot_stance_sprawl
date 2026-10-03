/// The supplied 2026–27 wrestling calendar. Later years repeat these month/day
/// dates until a new calendar is provided.
class SeasonDates {
  final String state;
  final DateTime seasonStart;
  final DateTime postseasonStart;

  const SeasonDates(this.state, this.seasonStart, this.postseasonStart);
}

final seasonDatesByState = <String, SeasonDates>{
  for (final dates in <SeasonDates>[
    SeasonDates('Alabama', DateTime(2026, 11, 12), DateTime(2027, 2, 11)),
    SeasonDates('Alaska', DateTime(2026, 10, 15), DateTime(2026, 12, 12)),
    SeasonDates('Arizona', DateTime(2026, 11, 23), DateTime(2027, 2, 13)),
    SeasonDates('Arkansas', DateTime(2026, 11, 12), DateTime(2027, 2, 6)),
    SeasonDates('California', DateTime(2026, 11, 6), DateTime(2027, 1, 30)),
    SeasonDates('Colorado', DateTime(2026, 11, 30), DateTime(2027, 2, 12)),
    SeasonDates('Connecticut', DateTime(2026, 12, 14), DateTime(2027, 2, 19)),
    SeasonDates('Delaware', DateTime(2026, 11, 30), DateTime(2027, 2, 5)),
    SeasonDates('Florida', DateTime(2026, 11, 23), DateTime(2027, 1, 14)),
    SeasonDates('Georgia', DateTime(2026, 11, 6), DateTime(2027, 1, 29)),
    SeasonDates('Hawaii', DateTime(2026, 11, 16), DateTime(2027, 2, 24)),
    SeasonDates('Idaho', DateTime(2026, 12, 2), DateTime(2027, 2, 20)),
    SeasonDates('Illinois', DateTime(2026, 11, 23), DateTime(2027, 1, 29)),
    SeasonDates('Indiana', DateTime(2026, 11, 16), DateTime(2027, 1, 30)),
    SeasonDates('Iowa', DateTime(2026, 11, 30), DateTime(2027, 2, 13)),
    SeasonDates('Kansas', DateTime(2026, 11, 30), DateTime(2027, 2, 12)),
    SeasonDates('Kentucky', DateTime(2026, 11, 23), DateTime(2027, 2, 7)),
    SeasonDates('Louisiana', DateTime(2026, 11, 2), DateTime(2027, 2, 12)),
    SeasonDates('Maine', DateTime(2026, 12, 3), DateTime(2027, 2, 6)),
    SeasonDates('Maryland', DateTime(2026, 12, 4), DateTime(2027, 2, 26)),
    SeasonDates('Massachusetts', DateTime(2026, 12, 10), DateTime(2027, 2, 13)),
    SeasonDates('Michigan', DateTime(2026, 12, 2), DateTime(2027, 2, 13)),
    SeasonDates('Minnesota', DateTime(2026, 12, 3), DateTime(2027, 2, 6)),
    SeasonDates('Mississippi', DateTime(2026, 10, 12), DateTime(2027, 2, 6)),
    SeasonDates('Missouri', DateTime(2026, 11, 15), DateTime(2027, 2, 5)),
    SeasonDates('Montana', DateTime(2026, 12, 3), DateTime(2027, 2, 13)),
    SeasonDates('Nebraska', DateTime(2026, 11, 23), DateTime(2027, 2, 14)),
    SeasonDates('Nevada', DateTime(2026, 11, 26), DateTime(2027, 1, 30)),
    SeasonDates('New Hampshire', DateTime(2026, 11, 29), DateTime(2027, 2, 20)),
    SeasonDates('New Jersey', DateTime(2026, 11, 30), DateTime(2027, 2, 13)),
    SeasonDates('New Mexico', DateTime(2026, 11, 2), DateTime(2027, 2, 12)),
    SeasonDates('New York', DateTime(2026, 11, 16), DateTime(2027, 1, 6)),
    SeasonDates(
        'North Carolina', DateTime(2026, 11, 11), DateTime(2027, 2, 12)),
    SeasonDates('North Dakota', DateTime(2026, 11, 20), DateTime(2027, 2, 12)),
    SeasonDates('Ohio', DateTime(2026, 12, 3), DateTime(2027, 2, 22)),
    SeasonDates('Oklahoma', DateTime(2026, 10, 1), DateTime(2027, 2, 13)),
    SeasonDates('Oregon', DateTime(2026, 12, 2), DateTime(2027, 2, 12)),
    SeasonDates('Pennsylvania', DateTime(2026, 12, 4), DateTime(2027, 2, 9)),
    SeasonDates('Rhode Island', DateTime(2026, 12, 10), DateTime(2027, 2, 13)),
    SeasonDates(
        'South Carolina', DateTime(2026, 11, 20), DateTime(2027, 1, 31)),
    SeasonDates('South Dakota', DateTime(2026, 11, 16), DateTime(2027, 2, 20)),
    SeasonDates('Tennessee', DateTime(2026, 10, 26), DateTime(2027, 1, 22)),
    SeasonDates('Texas', DateTime(2026, 11, 9), DateTime(2027, 1, 30)),
    SeasonDates('Utah', DateTime(2026, 11, 24), DateTime(2027, 2, 4)),
    SeasonDates('Vermont', DateTime(2026, 12, 6), DateTime(2027, 2, 26)),
    SeasonDates('Virginia', DateTime(2026, 11, 30), DateTime(2027, 2, 3)),
    SeasonDates('Washington', DateTime(2026, 11, 16), DateTime(2027, 2, 18)),
    SeasonDates('West Virginia', DateTime(2026, 12, 2), DateTime(2027, 2, 13)),
    SeasonDates('Wisconsin', DateTime(2026, 11, 27), DateTime(2027, 2, 5)),
    SeasonDates('Wyoming', DateTime(2026, 12, 10), DateTime(2027, 2, 19)),
  ])
    dates.state: dates,
};

enum SeasonCountdownPhase { seasonStart, postseasonStart, postseasonEnd }

class SeasonCountdown {
  final SeasonCountdownPhase phase;
  final DateTime targetDate;
  final int daysRemaining;

  const SeasonCountdown(this.phase, this.targetDate, this.daysRemaining);

  bool get isToday => daysRemaining == 0;

  String get title => switch (phase) {
        SeasonCountdownPhase.seasonStart => 'Season Start',
        SeasonCountdownPhase.postseasonStart => 'Post Season',
        SeasonCountdownPhase.postseasonEnd => 'Post Season is Over',
      };
}

SeasonCountdown countdownForState(String state, DateTime now) {
  final dates = seasonDatesByState[state];
  if (dates == null) throw ArgumentError.value(state, 'state', 'Unknown state');

  final today = DateTime.utc(now.year, now.month, now.day);
  // A winter postseason may belong to the season that started last year.
  var cycle = today.year - dates.seasonStart.year - 1;
  while (true) {
    final start = DateTime.utc(dates.seasonStart.year + cycle,
        dates.seasonStart.month, dates.seasonStart.day);
    final postseason = DateTime.utc(dates.postseasonStart.year + cycle,
        dates.postseasonStart.month, dates.postseasonStart.day);
    final end = postseason.add(const Duration(days: 21));
    if (today.isBefore(start)) {
      return SeasonCountdown(SeasonCountdownPhase.seasonStart, start,
          start.difference(today).inDays);
    }
    if (today.isAtSameMomentAs(start)) {
      return SeasonCountdown(SeasonCountdownPhase.seasonStart, start, 0);
    }
    if (today.isBefore(postseason) || today.isAtSameMomentAs(postseason)) {
      return SeasonCountdown(SeasonCountdownPhase.postseasonStart, postseason,
          postseason.difference(today).inDays);
    }
    if (!today.isAfter(end)) {
      return SeasonCountdown(SeasonCountdownPhase.postseasonEnd, end,
          end.difference(today).inDays);
    }
    cycle++;
  }
}
