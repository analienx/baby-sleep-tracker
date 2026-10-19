// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get navToday => 'Today';

  @override
  String get navHistory => 'History';

  @override
  String get navTrends => 'Trends';

  @override
  String get settingsTitle => 'Settings & privacy';

  @override
  String get settingsTooltip => 'Settings and privacy';

  @override
  String get appearanceHeading => 'Appearance';

  @override
  String get appearanceDescription =>
      'Choose the gentlest view for day and night.';

  @override
  String get appearanceSystem => 'Follow my phone';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get appearanceError =>
      'Could not save the appearance preference on this device.';

  @override
  String get familyHeading => 'Family';

  @override
  String get familyNotReady =>
      'Family accounts and invitations are not connected in this build. Your records are not shared with another parent.';

  @override
  String get familyInvite => 'Invite a caregiver';

  @override
  String get familyManage => 'Manage caregivers';

  @override
  String get familyUnavailable =>
      'Available after secure family sync is configured';

  @override
  String get exportHeading => 'Your records';

  @override
  String get exportDescription =>
      'Export the accepted sleep sessions visible on this device. The share sheet lets you save a copy. This does not include a cloud audit history or unreviewed conflicting versions.';

  @override
  String get exportWarning =>
      'Preview records may disappear on restart. Unsynced records may be lost if the app is removed. Keep an exported copy somewhere private.';

  @override
  String get exportJson => 'Share JSON';

  @override
  String get exportCsv => 'Share CSV';

  @override
  String get exportBusy => 'Preparing your file…';

  @override
  String get exportError =>
      'Could not prepare or share the export. Your records were not changed.';

  @override
  String get exportDismissed =>
      'Sharing cancelled. No file was confirmed saved.';

  @override
  String get exportDone =>
      'Share destination reported success. Check the destination for the file.';

  @override
  String get exportUnknown =>
      'The share sheet closed. Check that your file was saved.';

  @override
  String get deleteHeading => 'Deletion and recovery';

  @override
  String get deleteDescription =>
      'Remove individual rests in History, then Undo if needed. Account or household deletion is not available without authenticated family storage; no deletion request has been sent.';

  @override
  String get deleteHousehold => 'Delete household data';

  @override
  String get trendsTitle => 'Finding a rhythm.';

  @override
  String get trendsSubtitle => 'Gentle observations, without sleep scores.';

  @override
  String get trendsLast24 => 'Recorded in the last 24h';

  @override
  String get trendsObservation => 'Recorded sleep, not a sleep target.';

  @override
  String get trendsWeek => 'The last seven days';

  @override
  String get trendsWeekDescription =>
      'Sleep recorded on each local calendar day. Blank days mean no entries, not no sleep.';

  @override
  String get trendsCurrent => 'So far today';

  @override
  String get trendsNoRecords => 'No entries';

  @override
  String get trendsEmptyTitle => 'A little story starts here';

  @override
  String get trendsEmptyBody =>
      'Record a rest on Today or add one in History. Seven-day observations will grow with your entries.';

  @override
  String get trendsError =>
      'Sleep trends could not load. Try again after checking History.';

  @override
  String get trendsPartial =>
      'Today is still in progress. Totals may change when ongoing rests end.';

  @override
  String get trendsOverlap =>
      'Some rests overlap. Shared minutes count only once; review them in History.';

  @override
  String get trendsFootnote =>
      'These are observations from your log—not recommendations, scores or medical advice.';

  @override
  String trendsDayAccessible(String day, String value, String status) {
    return '$day: $value$status';
  }

  @override
  String get trendsTodayStatus => ', day not yet complete';

  @override
  String get trendsMissingStatus => ', no entry recorded';

  @override
  String get trendsNoStatus => '';
}
