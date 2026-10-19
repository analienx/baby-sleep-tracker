import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// No description provided for @navToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get navToday;

  /// No description provided for @navHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get navHistory;

  /// No description provided for @navTrends.
  ///
  /// In en, this message translates to:
  /// **'Trends'**
  String get navTrends;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings & privacy'**
  String get settingsTitle;

  /// No description provided for @settingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings and privacy'**
  String get settingsTooltip;

  /// No description provided for @appearanceHeading.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceHeading;

  /// No description provided for @appearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose the gentlest view for day and night.'**
  String get appearanceDescription;

  /// No description provided for @appearanceSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow my phone'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get appearanceDark;

  /// No description provided for @appearanceError.
  ///
  /// In en, this message translates to:
  /// **'Could not save the appearance preference on this device.'**
  String get appearanceError;

  /// No description provided for @familyHeading.
  ///
  /// In en, this message translates to:
  /// **'Family'**
  String get familyHeading;

  /// No description provided for @familyNotReady.
  ///
  /// In en, this message translates to:
  /// **'Family accounts and invitations are not connected in this build. Your records are not shared with another parent.'**
  String get familyNotReady;

  /// No description provided for @familyInvite.
  ///
  /// In en, this message translates to:
  /// **'Invite a caregiver'**
  String get familyInvite;

  /// No description provided for @familyManage.
  ///
  /// In en, this message translates to:
  /// **'Manage caregivers'**
  String get familyManage;

  /// No description provided for @familyUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Available after secure family sync is configured'**
  String get familyUnavailable;

  /// No description provided for @exportHeading.
  ///
  /// In en, this message translates to:
  /// **'Your records'**
  String get exportHeading;

  /// No description provided for @exportDescription.
  ///
  /// In en, this message translates to:
  /// **'Export the accepted sleep sessions visible on this device. The share sheet lets you save a copy. This does not include a cloud audit history or unreviewed conflicting versions.'**
  String get exportDescription;

  /// No description provided for @exportWarning.
  ///
  /// In en, this message translates to:
  /// **'Preview records may disappear on restart. Unsynced records may be lost if the app is removed. Keep an exported copy somewhere private.'**
  String get exportWarning;

  /// No description provided for @exportJson.
  ///
  /// In en, this message translates to:
  /// **'Share JSON'**
  String get exportJson;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Share CSV'**
  String get exportCsv;

  /// No description provided for @exportBusy.
  ///
  /// In en, this message translates to:
  /// **'Preparing your file…'**
  String get exportBusy;

  /// No description provided for @exportError.
  ///
  /// In en, this message translates to:
  /// **'Could not prepare or share the export. Your records were not changed.'**
  String get exportError;

  /// No description provided for @exportDismissed.
  ///
  /// In en, this message translates to:
  /// **'Sharing cancelled. No file was confirmed saved.'**
  String get exportDismissed;

  /// No description provided for @exportDone.
  ///
  /// In en, this message translates to:
  /// **'Share destination reported success. Check the destination for the file.'**
  String get exportDone;

  /// No description provided for @exportUnknown.
  ///
  /// In en, this message translates to:
  /// **'The share sheet closed. Check that your file was saved.'**
  String get exportUnknown;

  /// No description provided for @deleteHeading.
  ///
  /// In en, this message translates to:
  /// **'Deletion and recovery'**
  String get deleteHeading;

  /// No description provided for @deleteDescription.
  ///
  /// In en, this message translates to:
  /// **'Remove individual rests in History, then Undo if needed. Account or household deletion is not available without authenticated family storage; no deletion request has been sent.'**
  String get deleteDescription;

  /// No description provided for @deleteHousehold.
  ///
  /// In en, this message translates to:
  /// **'Delete household data'**
  String get deleteHousehold;

  /// No description provided for @trendsTitle.
  ///
  /// In en, this message translates to:
  /// **'Finding a rhythm.'**
  String get trendsTitle;

  /// No description provided for @trendsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Gentle observations, without sleep scores.'**
  String get trendsSubtitle;

  /// No description provided for @trendsLast24.
  ///
  /// In en, this message translates to:
  /// **'Recorded in the last 24h'**
  String get trendsLast24;

  /// No description provided for @trendsObservation.
  ///
  /// In en, this message translates to:
  /// **'Recorded sleep, not a sleep target.'**
  String get trendsObservation;

  /// No description provided for @trendsWeek.
  ///
  /// In en, this message translates to:
  /// **'The last seven days'**
  String get trendsWeek;

  /// No description provided for @trendsWeekDescription.
  ///
  /// In en, this message translates to:
  /// **'Sleep recorded on each local calendar day. Blank days mean no entries, not no sleep.'**
  String get trendsWeekDescription;

  /// No description provided for @trendsCurrent.
  ///
  /// In en, this message translates to:
  /// **'So far today'**
  String get trendsCurrent;

  /// No description provided for @trendsNoRecords.
  ///
  /// In en, this message translates to:
  /// **'No entries'**
  String get trendsNoRecords;

  /// No description provided for @trendsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'A little story starts here'**
  String get trendsEmptyTitle;

  /// No description provided for @trendsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Record a rest on Today or add one in History. Seven-day observations will grow with your entries.'**
  String get trendsEmptyBody;

  /// No description provided for @trendsError.
  ///
  /// In en, this message translates to:
  /// **'Sleep trends could not load. Try again after checking History.'**
  String get trendsError;

  /// No description provided for @trendsPartial.
  ///
  /// In en, this message translates to:
  /// **'Today is still in progress. Totals may change when ongoing rests end.'**
  String get trendsPartial;

  /// No description provided for @trendsOverlap.
  ///
  /// In en, this message translates to:
  /// **'Some rests overlap. Shared minutes count only once; review them in History.'**
  String get trendsOverlap;

  /// No description provided for @trendsFootnote.
  ///
  /// In en, this message translates to:
  /// **'These are observations from your log—not recommendations, scores or medical advice.'**
  String get trendsFootnote;

  /// No description provided for @trendsDayAccessible.
  ///
  /// In en, this message translates to:
  /// **'{day}: {value}{status}'**
  String trendsDayAccessible(String day, String value, String status);

  /// No description provided for @trendsTodayStatus.
  ///
  /// In en, this message translates to:
  /// **', day not yet complete'**
  String get trendsTodayStatus;

  /// No description provided for @trendsMissingStatus.
  ///
  /// In en, this message translates to:
  /// **', no entry recorded'**
  String get trendsMissingStatus;

  /// No description provided for @trendsNoStatus.
  ///
  /// In en, this message translates to:
  /// **''**
  String get trendsNoStatus;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
