import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
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
/// import 'localization/app_localizations.dart';
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
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('en'),
  ];

  /// No description provided for @appName.
  ///
  /// In ar, this message translates to:
  /// **'Wings'**
  String get appName;

  /// No description provided for @navLatest.
  ///
  /// In ar, this message translates to:
  /// **'الأحدث'**
  String get navLatest;

  /// No description provided for @navExplore.
  ///
  /// In ar, this message translates to:
  /// **'استكشف'**
  String get navExplore;

  /// No description provided for @navLibrary.
  ///
  /// In ar, this message translates to:
  /// **'مكتبتي'**
  String get navLibrary;

  /// No description provided for @navSettings.
  ///
  /// In ar, this message translates to:
  /// **'الإعدادات'**
  String get navSettings;

  /// No description provided for @commonRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get commonRetry;

  /// No description provided for @commonCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get commonCancel;

  /// No description provided for @commonConfirm.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد'**
  String get commonConfirm;

  /// No description provided for @commonSave.
  ///
  /// In ar, this message translates to:
  /// **'حفظ'**
  String get commonSave;

  /// No description provided for @commonClose.
  ///
  /// In ar, this message translates to:
  /// **'إغلاق'**
  String get commonClose;

  /// No description provided for @commonDelete.
  ///
  /// In ar, this message translates to:
  /// **'حذف'**
  String get commonDelete;

  /// No description provided for @commonRemove.
  ///
  /// In ar, this message translates to:
  /// **'إزالة'**
  String get commonRemove;

  /// No description provided for @commonClear.
  ///
  /// In ar, this message translates to:
  /// **'مسح'**
  String get commonClear;

  /// No description provided for @commonAll.
  ///
  /// In ar, this message translates to:
  /// **'الكل'**
  String get commonAll;

  /// No description provided for @commonMore.
  ///
  /// In ar, this message translates to:
  /// **'المزيد'**
  String get commonMore;

  /// No description provided for @commonSeeAll.
  ///
  /// In ar, this message translates to:
  /// **'عرض الكل'**
  String get commonSeeAll;

  /// No description provided for @commonShare.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة'**
  String get commonShare;

  /// No description provided for @commonDownload.
  ///
  /// In ar, this message translates to:
  /// **'تحميل'**
  String get commonDownload;

  /// No description provided for @commonPlay.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل'**
  String get commonPlay;

  /// No description provided for @commonLoading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ التحميل'**
  String get commonLoading;

  /// No description provided for @commonJustNow.
  ///
  /// In ar, this message translates to:
  /// **'الآن'**
  String get commonJustNow;

  /// No description provided for @commonMinutesAgo.
  ///
  /// In ar, this message translates to:
  /// **'قبل {count} دقيقة'**
  String commonMinutesAgo(int count);

  /// No description provided for @commonHoursAgo.
  ///
  /// In ar, this message translates to:
  /// **'قبل {count} ساعة'**
  String commonHoursAgo(int count);

  /// No description provided for @commonDaysAgo.
  ///
  /// In ar, this message translates to:
  /// **'قبل {count} يوم'**
  String commonDaysAgo(int count);

  /// No description provided for @commonYesterday.
  ///
  /// In ar, this message translates to:
  /// **'أمس'**
  String get commonYesterday;

  /// No description provided for @commonErrorTitle.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر إكمال الطلب'**
  String get commonErrorTitle;

  /// No description provided for @commonEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد شيء هنا'**
  String get commonEmptyTitle;

  /// No description provided for @commonEpisodeNumber.
  ///
  /// In ar, this message translates to:
  /// **'الحلقة {number}'**
  String commonEpisodeNumber(int number);

  /// No description provided for @commonList.
  ///
  /// In ar, this message translates to:
  /// **'قائمة'**
  String get commonList;

  /// No description provided for @commonGrid.
  ///
  /// In ar, this message translates to:
  /// **'شبكة'**
  String get commonGrid;

  /// No description provided for @commonApply.
  ///
  /// In ar, this message translates to:
  /// **'تطبيق'**
  String get commonApply;

  /// No description provided for @commonReset.
  ///
  /// In ar, this message translates to:
  /// **'إعادة تعيين'**
  String get commonReset;

  /// No description provided for @commonSort.
  ///
  /// In ar, this message translates to:
  /// **'ترتيب'**
  String get commonSort;

  /// No description provided for @commonFilter.
  ///
  /// In ar, this message translates to:
  /// **'تصفية'**
  String get commonFilter;

  /// No description provided for @commonType.
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get commonType;

  /// No description provided for @commonStatus.
  ///
  /// In ar, this message translates to:
  /// **'الحالة'**
  String get commonStatus;

  /// No description provided for @commonYear.
  ///
  /// In ar, this message translates to:
  /// **'السنة'**
  String get commonYear;

  /// No description provided for @commonGenre.
  ///
  /// In ar, this message translates to:
  /// **'التصنيف'**
  String get commonGenre;

  /// No description provided for @commonRating.
  ///
  /// In ar, this message translates to:
  /// **'التقييم'**
  String get commonRating;

  /// No description provided for @stateErrorNetwork.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر الاتصال بالشبكة. تحقّق من اتصالك وحاول مجدداً.'**
  String get stateErrorNetwork;

  /// No description provided for @stateErrorServer.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ في الخدمة مؤقتاً. حاول بعد قليل.'**
  String get stateErrorServer;

  /// No description provided for @stateErrorNotFound.
  ///
  /// In ar, this message translates to:
  /// **'لم نتمكن من العثور على هذا المحتوى.'**
  String get stateErrorNotFound;

  /// No description provided for @stateErrorTimeout.
  ///
  /// In ar, this message translates to:
  /// **'انتهت مدة الطلب. أعد المحاولة.'**
  String get stateErrorTimeout;

  /// No description provided for @stateErrorGeneric.
  ///
  /// In ar, this message translates to:
  /// **'حدث خطأ غير متوقع. أعد المحاولة.'**
  String get stateErrorGeneric;

  /// No description provided for @stateOffline.
  ///
  /// In ar, this message translates to:
  /// **'أنت غير متصل بالإنترنت'**
  String get stateOffline;

  /// No description provided for @stateOfflineBody.
  ///
  /// In ar, this message translates to:
  /// **'سنعرض المحتوى المحفوظ، وسيعود كل شيء عند استعادة الاتصال.'**
  String get stateOfflineBody;

  /// No description provided for @homeLatestEpisodes.
  ///
  /// In ar, this message translates to:
  /// **'أحدث الحلقات'**
  String get homeLatestEpisodes;

  /// No description provided for @homeRecentlyAdded.
  ///
  /// In ar, this message translates to:
  /// **'أضيف حديثاً'**
  String get homeRecentlyAdded;

  /// No description provided for @homePopular.
  ///
  /// In ar, this message translates to:
  /// **'الأكثر شعبية'**
  String get homePopular;

  /// No description provided for @homeContinueWatching.
  ///
  /// In ar, this message translates to:
  /// **'متابعة المشاهدة'**
  String get homeContinueWatching;

  /// No description provided for @homeRecommended.
  ///
  /// In ar, this message translates to:
  /// **'قد يعجبك'**
  String get homeRecommended;

  /// No description provided for @homeWatchNow.
  ///
  /// In ar, this message translates to:
  /// **'مشاهدة الآن'**
  String get homeWatchNow;

  /// No description provided for @homeMoreDetails.
  ///
  /// In ar, this message translates to:
  /// **'التفاصيل'**
  String get homeMoreDetails;

  /// No description provided for @homeLatestEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حلقات جديدة الآن'**
  String get homeLatestEmpty;

  /// No description provided for @homeNewBadge.
  ///
  /// In ar, this message translates to:
  /// **'جديد'**
  String get homeNewBadge;

  /// No description provided for @homeFeatured.
  ///
  /// In ar, this message translates to:
  /// **'مميّز'**
  String get homeFeatured;

  /// No description provided for @homeNextEpisode.
  ///
  /// In ar, this message translates to:
  /// **'الحلقة التالية'**
  String get homeNextEpisode;

  /// No description provided for @exploreTitle.
  ///
  /// In ar, this message translates to:
  /// **'استكشف'**
  String get exploreTitle;

  /// No description provided for @exploreSearchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن أنمي...'**
  String get exploreSearchHint;

  /// No description provided for @exploreGenres.
  ///
  /// In ar, this message translates to:
  /// **'التصنيفات'**
  String get exploreGenres;

  /// No description provided for @exploreBrowse.
  ///
  /// In ar, this message translates to:
  /// **'تصفّح'**
  String get exploreBrowse;

  /// No description provided for @exploreLatestAdded.
  ///
  /// In ar, this message translates to:
  /// **'أحدث الإضافات'**
  String get exploreLatestAdded;

  /// No description provided for @exploreTopRated.
  ///
  /// In ar, this message translates to:
  /// **'الأعلى تقييماً'**
  String get exploreTopRated;

  /// No description provided for @exploreMostPopular.
  ///
  /// In ar, this message translates to:
  /// **'الأكثر شعبية'**
  String get exploreMostPopular;

  /// No description provided for @exploreSort.
  ///
  /// In ar, this message translates to:
  /// **'الترتيب'**
  String get exploreSort;

  /// No description provided for @exploreSortNewest.
  ///
  /// In ar, this message translates to:
  /// **'الأحدث'**
  String get exploreSortNewest;

  /// No description provided for @exploreSortOldest.
  ///
  /// In ar, this message translates to:
  /// **'الأقدم'**
  String get exploreSortOldest;

  /// No description provided for @exploreSortAz.
  ///
  /// In ar, this message translates to:
  /// **'أبجدياً'**
  String get exploreSortAz;

  /// No description provided for @exploreSortPopular.
  ///
  /// In ar, this message translates to:
  /// **'الشعبية'**
  String get exploreSortPopular;

  /// No description provided for @exploreSortRating.
  ///
  /// In ar, this message translates to:
  /// **'التقييم'**
  String get exploreSortRating;

  /// No description provided for @exploreResults.
  ///
  /// In ar, this message translates to:
  /// **'{count} نتيجة'**
  String exploreResults(int count);

  /// No description provided for @exploreNoResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج مطابقة'**
  String get exploreNoResults;

  /// No description provided for @exploreFiltersTitle.
  ///
  /// In ar, this message translates to:
  /// **'خيارات التصفية'**
  String get exploreFiltersTitle;

  /// No description provided for @exploreFilterGenre.
  ///
  /// In ar, this message translates to:
  /// **'التصنيف'**
  String get exploreFilterGenre;

  /// No description provided for @exploreFilterYear.
  ///
  /// In ar, this message translates to:
  /// **'سنة الإصدار'**
  String get exploreFilterYear;

  /// No description provided for @exploreFilterStatus.
  ///
  /// In ar, this message translates to:
  /// **'الحالة'**
  String get exploreFilterStatus;

  /// No description provided for @exploreFilterType.
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get exploreFilterType;

  /// No description provided for @exploreRandom.
  ///
  /// In ar, this message translates to:
  /// **'أنمي عشوائي'**
  String get exploreRandom;

  /// No description provided for @searchTitle.
  ///
  /// In ar, this message translates to:
  /// **'البحث'**
  String get searchTitle;

  /// No description provided for @searchHint.
  ///
  /// In ar, this message translates to:
  /// **'اسم الأنمي بالعربية أو الإنجليزية'**
  String get searchHint;

  /// No description provided for @searchRecent.
  ///
  /// In ar, this message translates to:
  /// **'عمليات البحث الأخيرة'**
  String get searchRecent;

  /// No description provided for @searchClearAll.
  ///
  /// In ar, this message translates to:
  /// **'مسح الكل'**
  String get searchClearAll;

  /// No description provided for @searchEmptyTitle.
  ///
  /// In ar, this message translates to:
  /// **'ابحث عن أنميك'**
  String get searchEmptyTitle;

  /// No description provided for @searchEmptyBody.
  ///
  /// In ar, this message translates to:
  /// **'اكتب اسم الأنمي للعثور على الحلقات والتفاصيل.'**
  String get searchEmptyBody;

  /// No description provided for @searchNoResults.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد نتائج'**
  String get searchNoResults;

  /// No description provided for @searchNoResultsBody.
  ///
  /// In ar, this message translates to:
  /// **'جرّب اسماً آخر أو تهجئة مختلفة.'**
  String get searchNoResultsBody;

  /// No description provided for @searchStartTyping.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الكتابة للبحث'**
  String get searchStartTyping;

  /// No description provided for @detailsSynopsis.
  ///
  /// In ar, this message translates to:
  /// **'القصة'**
  String get detailsSynopsis;

  /// No description provided for @detailsMore.
  ///
  /// In ar, this message translates to:
  /// **'المزيد'**
  String get detailsMore;

  /// No description provided for @detailsLess.
  ///
  /// In ar, this message translates to:
  /// **'أقل'**
  String get detailsLess;

  /// No description provided for @detailsInfo.
  ///
  /// In ar, this message translates to:
  /// **'معلومات'**
  String get detailsInfo;

  /// No description provided for @detailsReleaseDate.
  ///
  /// In ar, this message translates to:
  /// **'تاريخ الإصدار'**
  String get detailsReleaseDate;

  /// No description provided for @detailsEpisodesCount.
  ///
  /// In ar, this message translates to:
  /// **'عدد الحلقات'**
  String get detailsEpisodesCount;

  /// No description provided for @detailsSeason.
  ///
  /// In ar, this message translates to:
  /// **'الموسم'**
  String get detailsSeason;

  /// No description provided for @detailsStudio.
  ///
  /// In ar, this message translates to:
  /// **'الاستوديو'**
  String get detailsStudio;

  /// No description provided for @detailsStatus.
  ///
  /// In ar, this message translates to:
  /// **'الحالة'**
  String get detailsStatus;

  /// No description provided for @detailsType.
  ///
  /// In ar, this message translates to:
  /// **'النوع'**
  String get detailsType;

  /// No description provided for @detailsGenres.
  ///
  /// In ar, this message translates to:
  /// **'التصنيفات'**
  String get detailsGenres;

  /// No description provided for @detailsRating.
  ///
  /// In ar, this message translates to:
  /// **'التقييم'**
  String get detailsRating;

  /// No description provided for @detailsEpisodes.
  ///
  /// In ar, this message translates to:
  /// **'الحلقات'**
  String get detailsEpisodes;

  /// No description provided for @detailsRelated.
  ///
  /// In ar, this message translates to:
  /// **'أنمي مشابه'**
  String get detailsRelated;

  /// No description provided for @detailsAddToLibrary.
  ///
  /// In ar, this message translates to:
  /// **'أضف إلى مكتبتي'**
  String get detailsAddToLibrary;

  /// No description provided for @detailsInLibrary.
  ///
  /// In ar, this message translates to:
  /// **'في مكتبتي'**
  String get detailsInLibrary;

  /// No description provided for @detailsShare.
  ///
  /// In ar, this message translates to:
  /// **'مشاركة'**
  String get detailsShare;

  /// No description provided for @detailsNoEpisodes.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حلقات متاحة لهذا الأنمي بعد'**
  String get detailsNoEpisodes;

  /// No description provided for @detailsPlanToWatch.
  ///
  /// In ar, this message translates to:
  /// **'سأشاهده لاحقاً'**
  String get detailsPlanToWatch;

  /// No description provided for @detailsCompleted.
  ///
  /// In ar, this message translates to:
  /// **'مكتمل'**
  String get detailsCompleted;

  /// No description provided for @detailsOnHold.
  ///
  /// In ar, this message translates to:
  /// **'مؤجل'**
  String get detailsOnHold;

  /// No description provided for @detailsDropped.
  ///
  /// In ar, this message translates to:
  /// **'متروك'**
  String get detailsDropped;

  /// No description provided for @detailsFavorites.
  ///
  /// In ar, this message translates to:
  /// **'المفضلة'**
  String get detailsFavorites;

  /// No description provided for @detailsWatching.
  ///
  /// In ar, this message translates to:
  /// **'أشاهده الآن'**
  String get detailsWatching;

  /// No description provided for @detailsAdded.
  ///
  /// In ar, this message translates to:
  /// **'أُضيف إلى مكتبتك'**
  String get detailsAdded;

  /// No description provided for @detailsRemoved.
  ///
  /// In ar, this message translates to:
  /// **'أُزيل من مكتبتك'**
  String get detailsRemoved;

  /// No description provided for @detailsWatch.
  ///
  /// In ar, this message translates to:
  /// **'مشاهدة'**
  String get detailsWatch;

  /// No description provided for @detailsDownloadSheetTitle.
  ///
  /// In ar, this message translates to:
  /// **'تنزيل الحلقة'**
  String get detailsDownloadSheetTitle;

  /// No description provided for @detailsDownloadSheetBody.
  ///
  /// In ar, this message translates to:
  /// **'اختر الجودة المتاحة لحفظ الحلقة على جهازك.'**
  String get detailsDownloadSheetBody;

  /// No description provided for @detailsNoDownloads.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد روابط قابلة للتنزيل لهذه الحلقة'**
  String get detailsNoDownloads;

  /// No description provided for @detailsBackdropUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'لا تتوفر صورة خلفية'**
  String get detailsBackdropUnavailable;

  /// No description provided for @detailsEpisodeWatched.
  ///
  /// In ar, this message translates to:
  /// **'تمت المشاهدة'**
  String get detailsEpisodeWatched;

  /// No description provided for @playerSpeed.
  ///
  /// In ar, this message translates to:
  /// **'سرعة التشغيل'**
  String get playerSpeed;

  /// No description provided for @playerQuality.
  ///
  /// In ar, this message translates to:
  /// **'الجودة'**
  String get playerQuality;

  /// No description provided for @playerNext.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get playerNext;

  /// No description provided for @playerPrevious.
  ///
  /// In ar, this message translates to:
  /// **'السابق'**
  String get playerPrevious;

  /// No description provided for @playerServers.
  ///
  /// In ar, this message translates to:
  /// **'السيرفرات'**
  String get playerServers;

  /// No description provided for @playerPlaybackError.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر تشغيل الحلقة'**
  String get playerPlaybackError;

  /// No description provided for @playerPlaybackErrorBody.
  ///
  /// In ar, this message translates to:
  /// **'جرّب سيرفراً آخر أو أعد المحاولة.'**
  String get playerPlaybackErrorBody;

  /// No description provided for @playerLoading.
  ///
  /// In ar, this message translates to:
  /// **'جارٍ تجهيز البث...'**
  String get playerLoading;

  /// No description provided for @playerNoServers.
  ///
  /// In ar, this message translates to:
  /// **'لا تتوفر سيرفرات لهذه الحلقة'**
  String get playerNoServers;

  /// No description provided for @playerAutoNextOn.
  ///
  /// In ar, this message translates to:
  /// **'التشغيل التلقائي مفعّل'**
  String get playerAutoNextOn;

  /// No description provided for @playerAutoNextOff.
  ///
  /// In ar, this message translates to:
  /// **'التشغيل التلقائي متوقف'**
  String get playerAutoNextOff;

  /// No description provided for @playerDirect.
  ///
  /// In ar, this message translates to:
  /// **'مباشر'**
  String get playerDirect;

  /// No description provided for @playerOpenInBrowser.
  ///
  /// In ar, this message translates to:
  /// **'فتح في المتصفح'**
  String get playerOpenInBrowser;

  /// No description provided for @playerSelectServer.
  ///
  /// In ar, this message translates to:
  /// **'اختر السيرفر'**
  String get playerSelectServer;

  /// No description provided for @playerSubtitles.
  ///
  /// In ar, this message translates to:
  /// **'الترجمة'**
  String get playerSubtitles;

  /// No description provided for @playerEpisode.
  ///
  /// In ar, this message translates to:
  /// **'الحلقة'**
  String get playerEpisode;

  /// No description provided for @playerAutoNext.
  ///
  /// In ar, this message translates to:
  /// **'التالي تلقائياً'**
  String get playerAutoNext;

  /// No description provided for @libraryTitle.
  ///
  /// In ar, this message translates to:
  /// **'مكتبتي'**
  String get libraryTitle;

  /// No description provided for @libraryFavorites.
  ///
  /// In ar, this message translates to:
  /// **'المفضلة'**
  String get libraryFavorites;

  /// No description provided for @libraryWatching.
  ///
  /// In ar, this message translates to:
  /// **'أشاهده'**
  String get libraryWatching;

  /// No description provided for @libraryCompleted.
  ///
  /// In ar, this message translates to:
  /// **'مكتمل'**
  String get libraryCompleted;

  /// No description provided for @libraryPlan.
  ///
  /// In ar, this message translates to:
  /// **'لاحقاً'**
  String get libraryPlan;

  /// No description provided for @libraryOnHold.
  ///
  /// In ar, this message translates to:
  /// **'مؤجل'**
  String get libraryOnHold;

  /// No description provided for @libraryDropped.
  ///
  /// In ar, this message translates to:
  /// **'متروك'**
  String get libraryDropped;

  /// No description provided for @libraryDownloaded.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get libraryDownloaded;

  /// No description provided for @libraryHistory.
  ///
  /// In ar, this message translates to:
  /// **'السجل'**
  String get libraryHistory;

  /// No description provided for @libraryEmptyFavorites.
  ///
  /// In ar, this message translates to:
  /// **'لم تضف أي أنمي إلى المفضلة بعد'**
  String get libraryEmptyFavorites;

  /// No description provided for @libraryEmptyGeneric.
  ///
  /// In ar, this message translates to:
  /// **'مكتبتك فارغة. ابدأ بإضافة أنمي يعجبك.'**
  String get libraryEmptyGeneric;

  /// No description provided for @libraryEmptyHistory.
  ///
  /// In ar, this message translates to:
  /// **'لم تشاهد أي حلقة بعد'**
  String get libraryEmptyHistory;

  /// No description provided for @libraryClearHistory.
  ///
  /// In ar, this message translates to:
  /// **'مسح سجل المشاهدة'**
  String get libraryClearHistory;

  /// No description provided for @libraryClearHistoryBody.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حذف سجل المشاهدة نهائياً من هذا الجهاز.'**
  String get libraryClearHistoryBody;

  /// No description provided for @libraryRemove.
  ///
  /// In ar, this message translates to:
  /// **'إزالة من المكتبة'**
  String get libraryRemove;

  /// No description provided for @libraryChangeStatus.
  ///
  /// In ar, this message translates to:
  /// **'تغيير الحالة'**
  String get libraryChangeStatus;

  /// No description provided for @librarySearchHint.
  ///
  /// In ar, this message translates to:
  /// **'ابحث في مكتبتك'**
  String get librarySearchHint;

  /// No description provided for @libraryHistoryContinue.
  ///
  /// In ar, this message translates to:
  /// **'متابعة'**
  String get libraryHistoryContinue;

  /// No description provided for @libraryProgress.
  ///
  /// In ar, this message translates to:
  /// **'اكتملت {percent}%'**
  String libraryProgress(int percent);

  /// No description provided for @libraryEmptySearch.
  ///
  /// In ar, this message translates to:
  /// **'لا يوجد أنمي مطابق في مكتبتك'**
  String get libraryEmptySearch;

  /// No description provided for @librarySortDate.
  ///
  /// In ar, this message translates to:
  /// **'الأحدث مشاهدة'**
  String get librarySortDate;

  /// No description provided for @librarySortTitle.
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get librarySortTitle;

  /// No description provided for @downloadsTitle.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get downloadsTitle;

  /// No description provided for @downloadsActive.
  ///
  /// In ar, this message translates to:
  /// **'قيد التنزيل'**
  String get downloadsActive;

  /// No description provided for @downloadsQueued.
  ///
  /// In ar, this message translates to:
  /// **'بالانتظار'**
  String get downloadsQueued;

  /// No description provided for @downloadsCompleted.
  ///
  /// In ar, this message translates to:
  /// **'مكتملة'**
  String get downloadsCompleted;

  /// No description provided for @downloadsFailed.
  ///
  /// In ar, this message translates to:
  /// **'فاشلة'**
  String get downloadsFailed;

  /// No description provided for @downloadsEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد تنزيلات بعد'**
  String get downloadsEmpty;

  /// No description provided for @downloadsPause.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف مؤقت'**
  String get downloadsPause;

  /// No description provided for @downloadsResume.
  ///
  /// In ar, this message translates to:
  /// **'استئناف'**
  String get downloadsResume;

  /// No description provided for @downloadsCancel.
  ///
  /// In ar, this message translates to:
  /// **'إلغاء'**
  String get downloadsCancel;

  /// No description provided for @downloadsRetry.
  ///
  /// In ar, this message translates to:
  /// **'إعادة المحاولة'**
  String get downloadsRetry;

  /// No description provided for @downloadsDelete.
  ///
  /// In ar, this message translates to:
  /// **'حذف الملف'**
  String get downloadsDelete;

  /// No description provided for @downloadsStorage.
  ///
  /// In ar, this message translates to:
  /// **'المساحة المستخدمة'**
  String get downloadsStorage;

  /// No description provided for @downloadsWifiHint.
  ///
  /// In ar, this message translates to:
  /// **'يُفضّل التنزيل عبر شبكة Wi-Fi'**
  String get downloadsWifiHint;

  /// No description provided for @downloadsPaused.
  ///
  /// In ar, this message translates to:
  /// **'متوقف مؤقتاً'**
  String get downloadsPaused;

  /// No description provided for @downloadsFailedBody.
  ///
  /// In ar, this message translates to:
  /// **'تعذّر إكمال التنزيل'**
  String get downloadsFailedBody;

  /// No description provided for @settingsAppearance.
  ///
  /// In ar, this message translates to:
  /// **'المظهر'**
  String get settingsAppearance;

  /// No description provided for @settingsTheme.
  ///
  /// In ar, this message translates to:
  /// **'السمة'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In ar, this message translates to:
  /// **'حسب النظام'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In ar, this message translates to:
  /// **'فاتح'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In ar, this message translates to:
  /// **'داكن'**
  String get settingsThemeDark;

  /// No description provided for @settingsPlayback.
  ///
  /// In ar, this message translates to:
  /// **'التشغيل'**
  String get settingsPlayback;

  /// No description provided for @settingsDefaultSpeed.
  ///
  /// In ar, this message translates to:
  /// **'السرعة الافتراضية'**
  String get settingsDefaultSpeed;

  /// No description provided for @settingsAutoNext.
  ///
  /// In ar, this message translates to:
  /// **'تشغيل الحلقة التالية تلقائياً'**
  String get settingsAutoNext;

  /// No description provided for @settingsRememberPosition.
  ///
  /// In ar, this message translates to:
  /// **'تذكّر موضع المشاهدة'**
  String get settingsRememberPosition;

  /// No description provided for @settingsDefaultQuality.
  ///
  /// In ar, this message translates to:
  /// **'الجودة المفضلة'**
  String get settingsDefaultQuality;

  /// No description provided for @settingsLanguage.
  ///
  /// In ar, this message translates to:
  /// **'اللغة'**
  String get settingsLanguage;

  /// No description provided for @settingsArabic.
  ///
  /// In ar, this message translates to:
  /// **'العربية'**
  String get settingsArabic;

  /// No description provided for @settingsEnglish.
  ///
  /// In ar, this message translates to:
  /// **'English'**
  String get settingsEnglish;

  /// No description provided for @settingsNotifications.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get settingsNotifications;

  /// No description provided for @settingsNotificationsEpisodes.
  ///
  /// In ar, this message translates to:
  /// **'حلقات جديدة'**
  String get settingsNotificationsEpisodes;

  /// No description provided for @settingsNotificationsDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get settingsNotificationsDownloads;

  /// No description provided for @settingsNotificationsGeneral.
  ///
  /// In ar, this message translates to:
  /// **'إشعارات عامة'**
  String get settingsNotificationsGeneral;

  /// No description provided for @settingsEnableAll.
  ///
  /// In ar, this message translates to:
  /// **'تفعيل الكل'**
  String get settingsEnableAll;

  /// No description provided for @settingsDisableAll.
  ///
  /// In ar, this message translates to:
  /// **'إيقاف الكل'**
  String get settingsDisableAll;

  /// No description provided for @settingsPermission.
  ///
  /// In ar, this message translates to:
  /// **'إذن الإشعارات'**
  String get settingsPermission;

  /// No description provided for @settingsPermissionGranted.
  ///
  /// In ar, this message translates to:
  /// **'مسموح'**
  String get settingsPermissionGranted;

  /// No description provided for @settingsPermissionDenied.
  ///
  /// In ar, this message translates to:
  /// **'غير مسموح'**
  String get settingsPermissionDenied;

  /// No description provided for @settingsPrivacy.
  ///
  /// In ar, this message translates to:
  /// **'الخصوصية والأمان'**
  String get settingsPrivacy;

  /// No description provided for @settingsClearCache.
  ///
  /// In ar, this message translates to:
  /// **'مسح ذاكرة التخزين المؤقت'**
  String get settingsClearCache;

  /// No description provided for @settingsClearSearch.
  ///
  /// In ar, this message translates to:
  /// **'مسح سجل البحث'**
  String get settingsClearSearch;

  /// No description provided for @settingsClearHistory.
  ///
  /// In ar, this message translates to:
  /// **'مسح سجل المشاهدة'**
  String get settingsClearHistory;

  /// No description provided for @settingsAbout.
  ///
  /// In ar, this message translates to:
  /// **'عن Wings'**
  String get settingsAbout;

  /// No description provided for @settingsVersion.
  ///
  /// In ar, this message translates to:
  /// **'الإصدار'**
  String get settingsVersion;

  /// No description provided for @settingsPrivacyPolicy.
  ///
  /// In ar, this message translates to:
  /// **'سياسة الخصوصية'**
  String get settingsPrivacyPolicy;

  /// No description provided for @settingsTerms.
  ///
  /// In ar, this message translates to:
  /// **'شروط الاستخدام'**
  String get settingsTerms;

  /// No description provided for @settingsAccount.
  ///
  /// In ar, this message translates to:
  /// **'الحساب'**
  String get settingsAccount;

  /// No description provided for @settingsSignIn.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get settingsSignIn;

  /// No description provided for @settingsSignOut.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الخروج'**
  String get settingsSignOut;

  /// No description provided for @settingsDeleteAccount.
  ///
  /// In ar, this message translates to:
  /// **'حذف الحساب'**
  String get settingsDeleteAccount;

  /// No description provided for @settingsProfile.
  ///
  /// In ar, this message translates to:
  /// **'الملف الشخصي'**
  String get settingsProfile;

  /// No description provided for @settingsDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get settingsDownloads;

  /// No description provided for @settingsCacheCleared.
  ///
  /// In ar, this message translates to:
  /// **'تم مسح ذاكرة التخزين المؤقت'**
  String get settingsCacheCleared;

  /// No description provided for @settingsHistoryCleared.
  ///
  /// In ar, this message translates to:
  /// **'تم مسح سجل المشاهدة'**
  String get settingsHistoryCleared;

  /// No description provided for @settingsSearchCleared.
  ///
  /// In ar, this message translates to:
  /// **'تم مسح سجل البحث'**
  String get settingsSearchCleared;

  /// No description provided for @settingsConfirmClearTitle.
  ///
  /// In ar, this message translates to:
  /// **'هل أنت متأكد؟'**
  String get settingsConfirmClearTitle;

  /// No description provided for @settingsGuest.
  ///
  /// In ar, this message translates to:
  /// **'زائر'**
  String get settingsGuest;

  /// No description provided for @settingsOpenSource.
  ///
  /// In ar, this message translates to:
  /// **'مفتوح المصدر'**
  String get settingsOpenSource;

  /// No description provided for @settingsStorage.
  ///
  /// In ar, this message translates to:
  /// **'مساحة التنزيلات'**
  String get settingsStorage;

  /// No description provided for @authWelcomeTitle.
  ///
  /// In ar, this message translates to:
  /// **'أهلاً بك في Wings'**
  String get authWelcomeTitle;

  /// No description provided for @authWelcomeBody.
  ///
  /// In ar, this message translates to:
  /// **'تابع أنميك المفضل، احفظ حلقاتك، وأكمل من حيث توقفت.'**
  String get authWelcomeBody;

  /// No description provided for @authLogin.
  ///
  /// In ar, this message translates to:
  /// **'تسجيل الدخول'**
  String get authLogin;

  /// No description provided for @authRegister.
  ///
  /// In ar, this message translates to:
  /// **'إنشاء حساب'**
  String get authRegister;

  /// No description provided for @authEmail.
  ///
  /// In ar, this message translates to:
  /// **'البريد الإلكتروني'**
  String get authEmail;

  /// No description provided for @authPassword.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور'**
  String get authPassword;

  /// No description provided for @authConfirmPassword.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد كلمة المرور'**
  String get authConfirmPassword;

  /// No description provided for @authName.
  ///
  /// In ar, this message translates to:
  /// **'الاسم'**
  String get authName;

  /// No description provided for @authForgot.
  ///
  /// In ar, this message translates to:
  /// **'نسيت كلمة المرور؟'**
  String get authForgot;

  /// No description provided for @authRemember.
  ///
  /// In ar, this message translates to:
  /// **'تذكرني'**
  String get authRemember;

  /// No description provided for @authNoAccount.
  ///
  /// In ar, this message translates to:
  /// **'ليس لديك حساب؟'**
  String get authNoAccount;

  /// No description provided for @authHaveAccount.
  ///
  /// In ar, this message translates to:
  /// **'لديك حساب بالفعل؟'**
  String get authHaveAccount;

  /// No description provided for @authSendReset.
  ///
  /// In ar, this message translates to:
  /// **'إرسال رابط الاستعادة'**
  String get authSendReset;

  /// No description provided for @authBackToLogin.
  ///
  /// In ar, this message translates to:
  /// **'العودة لتسجيل الدخول'**
  String get authBackToLogin;

  /// No description provided for @authVerifyTitle.
  ///
  /// In ar, this message translates to:
  /// **'تأكيد البريد الإلكتروني'**
  String get authVerifyTitle;

  /// No description provided for @authVerifyBody.
  ///
  /// In ar, this message translates to:
  /// **'أرسلنا رابط تأكيد إلى بريدك. افتح الرابط ثم أكمل الدخول.'**
  String get authVerifyBody;

  /// No description provided for @authUnavailable.
  ///
  /// In ar, this message translates to:
  /// **'الحساب السحابي غير مفعّل'**
  String get authUnavailable;

  /// No description provided for @authUnavailableBody.
  ///
  /// In ar, this message translates to:
  /// **'واجهات الحساب جاهزة، لكنها تنتظر ربط خدمة المصادقة. يمكنك استخدام Wings كزائر الآن.'**
  String get authUnavailableBody;

  /// No description provided for @authContinueGuest.
  ///
  /// In ar, this message translates to:
  /// **'المتابعة كزائر'**
  String get authContinueGuest;

  /// No description provided for @authValidationEmail.
  ///
  /// In ar, this message translates to:
  /// **'أدخل بريداً إلكترونياً صحيحاً'**
  String get authValidationEmail;

  /// No description provided for @authValidationPassword.
  ///
  /// In ar, this message translates to:
  /// **'كلمة المرور يجب أن تكون 8 أحرف على الأقل'**
  String get authValidationPassword;

  /// No description provided for @authValidationName.
  ///
  /// In ar, this message translates to:
  /// **'أدخل اسماً لا يقل عن حرفين'**
  String get authValidationName;

  /// No description provided for @authValidationConfirm.
  ///
  /// In ar, this message translates to:
  /// **'كلمتا المرور غير متطابقتين'**
  String get authValidationConfirm;

  /// No description provided for @authAcceptTerms.
  ///
  /// In ar, this message translates to:
  /// **'أوافق على شروط الاستخدام وسياسة الخصوصية'**
  String get authAcceptTerms;

  /// No description provided for @authResetSent.
  ///
  /// In ar, this message translates to:
  /// **'إذا كان البريد مسجلاً، فسيصلك رابط الاستعادة.'**
  String get authResetSent;

  /// No description provided for @profileTitle.
  ///
  /// In ar, this message translates to:
  /// **'الملف الشخصي'**
  String get profileTitle;

  /// No description provided for @profileGuest.
  ///
  /// In ar, this message translates to:
  /// **'حساب الزائر'**
  String get profileGuest;

  /// No description provided for @profileEdit.
  ///
  /// In ar, this message translates to:
  /// **'تعديل الملف'**
  String get profileEdit;

  /// No description provided for @profileStats.
  ///
  /// In ar, this message translates to:
  /// **'إحصاءاتك'**
  String get profileStats;

  /// No description provided for @profileFavorites.
  ///
  /// In ar, this message translates to:
  /// **'المفضلة'**
  String get profileFavorites;

  /// No description provided for @profileCompleted.
  ///
  /// In ar, this message translates to:
  /// **'مكتمل'**
  String get profileCompleted;

  /// No description provided for @profileWatching.
  ///
  /// In ar, this message translates to:
  /// **'أشاهده'**
  String get profileWatching;

  /// No description provided for @profileDownloads.
  ///
  /// In ar, this message translates to:
  /// **'التنزيلات'**
  String get profileDownloads;

  /// No description provided for @profileMemberSince.
  ///
  /// In ar, this message translates to:
  /// **'معنا منذ'**
  String get profileMemberSince;

  /// No description provided for @profileSignInPrompt.
  ///
  /// In ar, this message translates to:
  /// **'سجّل الدخول لمزامنة مكتبتك عبر أجهزتك.'**
  String get profileSignInPrompt;

  /// No description provided for @profileDeleteAccount.
  ///
  /// In ar, this message translates to:
  /// **'حذف الحساب'**
  String get profileDeleteAccount;

  /// No description provided for @profileDeleteBody.
  ///
  /// In ar, this message translates to:
  /// **'سيتم حذف حسابك وبياناتك السحابية. بياناتك المحلية تبقى حتى تمسحها.'**
  String get profileDeleteBody;

  /// No description provided for @profileDeleteDone.
  ///
  /// In ar, this message translates to:
  /// **'تم حذف الحساب'**
  String get profileDeleteDone;

  /// No description provided for @notificationsTitle.
  ///
  /// In ar, this message translates to:
  /// **'الإشعارات'**
  String get notificationsTitle;

  /// No description provided for @notificationsMarkAll.
  ///
  /// In ar, this message translates to:
  /// **'تعليم الكل كمقروء'**
  String get notificationsMarkAll;

  /// No description provided for @notificationsEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد إشعارات'**
  String get notificationsEmpty;

  /// No description provided for @notificationsSettings.
  ///
  /// In ar, this message translates to:
  /// **'إعدادات الإشعارات'**
  String get notificationsSettings;

  /// No description provided for @onboardingSkip.
  ///
  /// In ar, this message translates to:
  /// **'تخطي'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get onboardingNext;

  /// No description provided for @onboardingStart.
  ///
  /// In ar, this message translates to:
  /// **'ابدأ الآن'**
  String get onboardingStart;

  /// No description provided for @onboardingTitle1.
  ///
  /// In ar, this message translates to:
  /// **'اكتشف أنميك المفضل'**
  String get onboardingTitle1;

  /// No description provided for @onboardingBody1.
  ///
  /// In ar, this message translates to:
  /// **'أحدث الحلقات، الأنمي الموسمي، والأعمال الأعلى تقييماً في مكان واحد.'**
  String get onboardingBody1;

  /// No description provided for @onboardingTitle2.
  ///
  /// In ar, this message translates to:
  /// **'شاهد بأفضل جودة'**
  String get onboardingTitle2;

  /// No description provided for @onboardingBody2.
  ///
  /// In ar, this message translates to:
  /// **'مشغّل سريع مع اختيار الجودة والسرعة، وتذكّر موضع المشاهدة تلقائياً.'**
  String get onboardingBody2;

  /// No description provided for @onboardingTitle3.
  ///
  /// In ar, this message translates to:
  /// **'مكتبتك معك'**
  String get onboardingTitle3;

  /// No description provided for @onboardingBody3.
  ///
  /// In ar, this message translates to:
  /// **'أضف للمفضلة، نزّل الحلقات، وتابع من حيث توقفت في أي وقت.'**
  String get onboardingBody3;

  /// No description provided for @genreTitle.
  ///
  /// In ar, this message translates to:
  /// **'تصنيف: {name}'**
  String genreTitle(String name);

  /// No description provided for @genreEmpty.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد أعمال في هذا التصنيف'**
  String get genreEmpty;

  /// No description provided for @statusOngoing.
  ///
  /// In ar, this message translates to:
  /// **'مستمر'**
  String get statusOngoing;

  /// No description provided for @statusCompleted.
  ///
  /// In ar, this message translates to:
  /// **'مكتمل'**
  String get statusCompleted;

  /// No description provided for @typeSeries.
  ///
  /// In ar, this message translates to:
  /// **'مسلسل'**
  String get typeSeries;

  /// No description provided for @typeMovie.
  ///
  /// In ar, this message translates to:
  /// **'فيلم'**
  String get typeMovie;

  /// No description provided for @errorNoEpisodes.
  ///
  /// In ar, this message translates to:
  /// **'لا توجد حلقات'**
  String get errorNoEpisodes;

  /// No description provided for @searchHistoryRemoved.
  ///
  /// In ar, this message translates to:
  /// **'حُذف من السجل'**
  String get searchHistoryRemoved;

  /// No description provided for @commonNext.
  ///
  /// In ar, this message translates to:
  /// **'التالي'**
  String get commonNext;

  /// No description provided for @commonBack.
  ///
  /// In ar, this message translates to:
  /// **'رجوع'**
  String get commonBack;

  /// No description provided for @authUsername.
  ///
  /// In ar, this message translates to:
  /// **'اسم المستخدم'**
  String get authUsername;

  /// No description provided for @authValidationUsername.
  ///
  /// In ar, this message translates to:
  /// **'3–20 حرفاً إنجليزياً أو رقماً أو _'**
  String get authValidationUsername;

  /// No description provided for @authCountry.
  ///
  /// In ar, this message translates to:
  /// **'الدولة'**
  String get authCountry;

  /// No description provided for @authChoosePhoto.
  ///
  /// In ar, this message translates to:
  /// **'تغيير الصورة'**
  String get authChoosePhoto;

  /// No description provided for @authStepOf.
  ///
  /// In ar, this message translates to:
  /// **'الخطوة {current} من {total}'**
  String authStepOf(String current, String total);

  /// No description provided for @authPasswordWeak.
  ///
  /// In ar, this message translates to:
  /// **'ضعيفة'**
  String get authPasswordWeak;

  /// No description provided for @authPasswordMedium.
  ///
  /// In ar, this message translates to:
  /// **'متوسطة'**
  String get authPasswordMedium;

  /// No description provided for @authPasswordStrong.
  ///
  /// In ar, this message translates to:
  /// **'قوية'**
  String get authPasswordStrong;

  /// No description provided for @notificationsEpisodeBody.
  ///
  /// In ar, this message translates to:
  /// **'الحلقة {number} متاحة الآن 🎉 اضغط للمشاهدة'**
  String notificationsEpisodeBody(int number);
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
      <String>['ar', 'en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
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
