// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appName => 'Wings';

  @override
  String get navLatest => 'الأحدث';

  @override
  String get navExplore => 'استكشف';

  @override
  String get navLibrary => 'مكتبتي';

  @override
  String get navSettings => 'الإعدادات';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonConfirm => 'تأكيد';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonClose => 'إغلاق';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonRemove => 'إزالة';

  @override
  String get commonClear => 'مسح';

  @override
  String get commonAll => 'الكل';

  @override
  String get commonMore => 'المزيد';

  @override
  String get commonSeeAll => 'عرض الكل';

  @override
  String get commonShare => 'مشاركة';

  @override
  String get commonDownload => 'تحميل';

  @override
  String get commonPlay => 'تشغيل';

  @override
  String get commonLoading => 'جارٍ التحميل';

  @override
  String get commonJustNow => 'الآن';

  @override
  String commonMinutesAgo(int count) {
    return 'قبل $count دقيقة';
  }

  @override
  String commonHoursAgo(int count) {
    return 'قبل $count ساعة';
  }

  @override
  String commonDaysAgo(int count) {
    return 'قبل $count يوم';
  }

  @override
  String get commonYesterday => 'أمس';

  @override
  String get commonErrorTitle => 'تعذّر إكمال الطلب';

  @override
  String get commonEmptyTitle => 'لا يوجد شيء هنا';

  @override
  String commonEpisodeNumber(int number) {
    return 'الحلقة $number';
  }

  @override
  String get commonList => 'قائمة';

  @override
  String get commonGrid => 'شبكة';

  @override
  String get commonApply => 'تطبيق';

  @override
  String get commonReset => 'إعادة تعيين';

  @override
  String get commonSort => 'ترتيب';

  @override
  String get commonFilter => 'تصفية';

  @override
  String get commonType => 'النوع';

  @override
  String get commonStatus => 'الحالة';

  @override
  String get commonYear => 'السنة';

  @override
  String get commonGenre => 'التصنيف';

  @override
  String get commonRating => 'التقييم';

  @override
  String get stateErrorNetwork =>
      'تعذّر الاتصال بالشبكة. تحقّق من اتصالك وحاول مجدداً.';

  @override
  String get stateErrorServer => 'حدث خطأ في الخدمة مؤقتاً. حاول بعد قليل.';

  @override
  String get stateErrorNotFound => 'لم نتمكن من العثور على هذا المحتوى.';

  @override
  String get stateErrorTimeout => 'انتهت مدة الطلب. أعد المحاولة.';

  @override
  String get stateErrorGeneric => 'حدث خطأ غير متوقع. أعد المحاولة.';

  @override
  String get stateOffline => 'أنت غير متصل بالإنترنت';

  @override
  String get stateOfflineBody =>
      'سنعرض المحتوى المحفوظ، وسيعود كل شيء عند استعادة الاتصال.';

  @override
  String get homeLatestEpisodes => 'أحدث الحلقات';

  @override
  String get homeRecentlyAdded => 'أضيف حديثاً';

  @override
  String get homePopular => 'الأكثر شعبية';

  @override
  String get homeContinueWatching => 'متابعة المشاهدة';

  @override
  String get homeRecommended => 'قد يعجبك';

  @override
  String get homeWatchNow => 'مشاهدة الآن';

  @override
  String get homeMoreDetails => 'التفاصيل';

  @override
  String get homeLatestEmpty => 'لا توجد حلقات جديدة الآن';

  @override
  String get homeNewBadge => 'جديد';

  @override
  String get homeFeatured => 'مميّز';

  @override
  String get homeNextEpisode => 'الحلقة التالية';

  @override
  String get exploreTitle => 'استكشف';

  @override
  String get exploreSearchHint => 'ابحث عن أنمي...';

  @override
  String get exploreGenres => 'التصنيفات';

  @override
  String get exploreBrowse => 'تصفّح';

  @override
  String get exploreLatestAdded => 'أحدث الإضافات';

  @override
  String get exploreTopRated => 'الأعلى تقييماً';

  @override
  String get exploreMostPopular => 'الأكثر شعبية';

  @override
  String get exploreSort => 'الترتيب';

  @override
  String get exploreSortNewest => 'الأحدث';

  @override
  String get exploreSortOldest => 'الأقدم';

  @override
  String get exploreSortAz => 'أبجدياً';

  @override
  String get exploreSortPopular => 'الشعبية';

  @override
  String get exploreSortRating => 'التقييم';

  @override
  String exploreResults(int count) {
    return '$count نتيجة';
  }

  @override
  String get exploreNoResults => 'لا توجد نتائج مطابقة';

  @override
  String get exploreFiltersTitle => 'خيارات التصفية';

  @override
  String get exploreFilterGenre => 'التصنيف';

  @override
  String get exploreFilterYear => 'سنة الإصدار';

  @override
  String get exploreFilterStatus => 'الحالة';

  @override
  String get exploreFilterType => 'النوع';

  @override
  String get exploreRandom => 'أنمي عشوائي';

  @override
  String get searchTitle => 'البحث';

  @override
  String get searchHint => 'اسم الأنمي بالعربية أو الإنجليزية';

  @override
  String get searchRecent => 'عمليات البحث الأخيرة';

  @override
  String get searchClearAll => 'مسح الكل';

  @override
  String get searchEmptyTitle => 'ابحث عن أنميك';

  @override
  String get searchEmptyBody => 'اكتب اسم الأنمي للعثور على الحلقات والتفاصيل.';

  @override
  String get searchNoResults => 'لا توجد نتائج';

  @override
  String get searchNoResultsBody => 'جرّب اسماً آخر أو تهجئة مختلفة.';

  @override
  String get searchStartTyping => 'ابدأ الكتابة للبحث';

  @override
  String get detailsSynopsis => 'القصة';

  @override
  String get detailsMore => 'المزيد';

  @override
  String get detailsLess => 'أقل';

  @override
  String get detailsInfo => 'معلومات';

  @override
  String get detailsReleaseDate => 'تاريخ الإصدار';

  @override
  String get detailsEpisodesCount => 'عدد الحلقات';

  @override
  String get detailsSeason => 'الموسم';

  @override
  String get detailsStudio => 'الاستوديو';

  @override
  String get detailsStatus => 'الحالة';

  @override
  String get detailsType => 'النوع';

  @override
  String get detailsGenres => 'التصنيفات';

  @override
  String get detailsRating => 'التقييم';

  @override
  String get detailsEpisodes => 'الحلقات';

  @override
  String get detailsRelated => 'أنمي مشابه';

  @override
  String get detailsAddToLibrary => 'أضف إلى مكتبتي';

  @override
  String get detailsInLibrary => 'في مكتبتي';

  @override
  String get detailsShare => 'مشاركة';

  @override
  String get detailsNoEpisodes => 'لا توجد حلقات متاحة لهذا الأنمي بعد';

  @override
  String get detailsPlanToWatch => 'سأشاهده لاحقاً';

  @override
  String get detailsCompleted => 'مكتمل';

  @override
  String get detailsOnHold => 'مؤجل';

  @override
  String get detailsDropped => 'متروك';

  @override
  String get detailsFavorites => 'المفضلة';

  @override
  String get detailsWatching => 'أشاهده الآن';

  @override
  String get detailsAdded => 'أُضيف إلى مكتبتك';

  @override
  String get detailsRemoved => 'أُزيل من مكتبتك';

  @override
  String get detailsWatch => 'مشاهدة';

  @override
  String get detailsDownloadSheetTitle => 'تنزيل الحلقة';

  @override
  String get detailsDownloadSheetBody =>
      'اختر الجودة المتاحة لحفظ الحلقة على جهازك.';

  @override
  String get detailsNoDownloads => 'لا توجد روابط قابلة للتنزيل لهذه الحلقة';

  @override
  String get detailsBackdropUnavailable => 'لا تتوفر صورة خلفية';

  @override
  String get detailsEpisodeWatched => 'تمت المشاهدة';

  @override
  String get playerSpeed => 'سرعة التشغيل';

  @override
  String get playerQuality => 'الجودة';

  @override
  String get playerNext => 'التالي';

  @override
  String get playerPrevious => 'السابق';

  @override
  String get playerServers => 'السيرفرات';

  @override
  String get playerPlaybackError => 'تعذّر تشغيل الحلقة';

  @override
  String get playerPlaybackErrorBody => 'جرّب سيرفراً آخر أو أعد المحاولة.';

  @override
  String get playerLoading => 'جارٍ تجهيز البث...';

  @override
  String get playerNoServers => 'لا تتوفر سيرفرات لهذه الحلقة';

  @override
  String get playerAutoNextOn => 'التشغيل التلقائي مفعّل';

  @override
  String get playerAutoNextOff => 'التشغيل التلقائي متوقف';

  @override
  String get playerDirect => 'مباشر';

  @override
  String get playerOpenInBrowser => 'فتح في المتصفح';

  @override
  String get playerSelectServer => 'اختر السيرفر';

  @override
  String get playerSubtitles => 'الترجمة';

  @override
  String get playerEpisode => 'الحلقة';

  @override
  String get playerAutoNext => 'التالي تلقائياً';

  @override
  String get libraryTitle => 'مكتبتي';

  @override
  String get libraryFavorites => 'المفضلة';

  @override
  String get libraryWatching => 'أشاهده';

  @override
  String get libraryCompleted => 'مكتمل';

  @override
  String get libraryPlan => 'لاحقاً';

  @override
  String get libraryOnHold => 'مؤجل';

  @override
  String get libraryDropped => 'متروك';

  @override
  String get libraryDownloaded => 'التنزيلات';

  @override
  String get libraryHistory => 'السجل';

  @override
  String get libraryEmptyFavorites => 'لم تضف أي أنمي إلى المفضلة بعد';

  @override
  String get libraryEmptyGeneric => 'مكتبتك فارغة. ابدأ بإضافة أنمي يعجبك.';

  @override
  String get libraryEmptyHistory => 'لم تشاهد أي حلقة بعد';

  @override
  String get libraryClearHistory => 'مسح سجل المشاهدة';

  @override
  String get libraryClearHistoryBody =>
      'سيتم حذف سجل المشاهدة نهائياً من هذا الجهاز.';

  @override
  String get libraryRemove => 'إزالة من المكتبة';

  @override
  String get libraryChangeStatus => 'تغيير الحالة';

  @override
  String get librarySearchHint => 'ابحث في مكتبتك';

  @override
  String get libraryHistoryContinue => 'متابعة';

  @override
  String libraryProgress(int percent) {
    return 'اكتملت $percent%';
  }

  @override
  String get libraryEmptySearch => 'لا يوجد أنمي مطابق في مكتبتك';

  @override
  String get librarySortDate => 'الأحدث مشاهدة';

  @override
  String get librarySortTitle => 'الاسم';

  @override
  String get downloadsTitle => 'التنزيلات';

  @override
  String get downloadsActive => 'قيد التنزيل';

  @override
  String get downloadsQueued => 'بالانتظار';

  @override
  String get downloadsCompleted => 'مكتملة';

  @override
  String get downloadsFailed => 'فاشلة';

  @override
  String get downloadsEmpty => 'لا توجد تنزيلات بعد';

  @override
  String get downloadsPause => 'إيقاف مؤقت';

  @override
  String get downloadsResume => 'استئناف';

  @override
  String get downloadsCancel => 'إلغاء';

  @override
  String get downloadsRetry => 'إعادة المحاولة';

  @override
  String get downloadsDelete => 'حذف الملف';

  @override
  String get downloadsStorage => 'المساحة المستخدمة';

  @override
  String get downloadsWifiHint => 'يُفضّل التنزيل عبر شبكة Wi-Fi';

  @override
  String get downloadsPaused => 'متوقف مؤقتاً';

  @override
  String get downloadsFailedBody => 'تعذّر إكمال التنزيل';

  @override
  String get settingsAppearance => 'المظهر';

  @override
  String get settingsTheme => 'السمة';

  @override
  String get settingsThemeSystem => 'حسب النظام';

  @override
  String get settingsThemeLight => 'فاتح';

  @override
  String get settingsThemeDark => 'داكن';

  @override
  String get settingsPlayback => 'التشغيل';

  @override
  String get settingsDefaultSpeed => 'السرعة الافتراضية';

  @override
  String get settingsAutoNext => 'تشغيل الحلقة التالية تلقائياً';

  @override
  String get settingsRememberPosition => 'تذكّر موضع المشاهدة';

  @override
  String get settingsDefaultQuality => 'الجودة المفضلة';

  @override
  String get settingsLanguage => 'اللغة';

  @override
  String get settingsArabic => 'العربية';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsNotifications => 'الإشعارات';

  @override
  String get settingsNotificationsEpisodes => 'حلقات جديدة';

  @override
  String get settingsNotificationsDownloads => 'التنزيلات';

  @override
  String get settingsNotificationsGeneral => 'إشعارات عامة';

  @override
  String get settingsEnableAll => 'تفعيل الكل';

  @override
  String get settingsDisableAll => 'إيقاف الكل';

  @override
  String get settingsPermission => 'إذن الإشعارات';

  @override
  String get settingsPermissionGranted => 'مسموح';

  @override
  String get settingsPermissionDenied => 'غير مسموح';

  @override
  String get settingsPrivacy => 'الخصوصية والأمان';

  @override
  String get settingsClearCache => 'مسح ذاكرة التخزين المؤقت';

  @override
  String get settingsClearSearch => 'مسح سجل البحث';

  @override
  String get settingsClearHistory => 'مسح سجل المشاهدة';

  @override
  String get settingsAbout => 'عن Wings';

  @override
  String get settingsVersion => 'الإصدار';

  @override
  String get settingsPrivacyPolicy => 'سياسة الخصوصية';

  @override
  String get settingsTerms => 'شروط الاستخدام';

  @override
  String get settingsAccount => 'الحساب';

  @override
  String get settingsSignIn => 'تسجيل الدخول';

  @override
  String get settingsSignOut => 'تسجيل الخروج';

  @override
  String get settingsDeleteAccount => 'حذف الحساب';

  @override
  String get settingsProfile => 'الملف الشخصي';

  @override
  String get settingsDownloads => 'التنزيلات';

  @override
  String get settingsCacheCleared => 'تم مسح ذاكرة التخزين المؤقت';

  @override
  String get settingsHistoryCleared => 'تم مسح سجل المشاهدة';

  @override
  String get settingsSearchCleared => 'تم مسح سجل البحث';

  @override
  String get settingsConfirmClearTitle => 'هل أنت متأكد؟';

  @override
  String get settingsGuest => 'زائر';

  @override
  String get settingsOpenSource => 'مفتوح المصدر';

  @override
  String get settingsStorage => 'مساحة التنزيلات';

  @override
  String get authWelcomeTitle => 'أهلاً بك في Wings';

  @override
  String get authWelcomeBody =>
      'تابع أنميك المفضل، احفظ حلقاتك، وأكمل من حيث توقفت.';

  @override
  String get authLogin => 'تسجيل الدخول';

  @override
  String get authRegister => 'إنشاء حساب';

  @override
  String get authEmail => 'البريد الإلكتروني';

  @override
  String get authPassword => 'كلمة المرور';

  @override
  String get authConfirmPassword => 'تأكيد كلمة المرور';

  @override
  String get authName => 'الاسم';

  @override
  String get authForgot => 'نسيت كلمة المرور؟';

  @override
  String get authRemember => 'تذكرني';

  @override
  String get authNoAccount => 'ليس لديك حساب؟';

  @override
  String get authHaveAccount => 'لديك حساب بالفعل؟';

  @override
  String get authSendReset => 'إرسال رابط الاستعادة';

  @override
  String get authBackToLogin => 'العودة لتسجيل الدخول';

  @override
  String get authVerifyTitle => 'تأكيد البريد الإلكتروني';

  @override
  String get authVerifyBody =>
      'أرسلنا رابط تأكيد إلى بريدك. افتح الرابط ثم أكمل الدخول.';

  @override
  String get authUnavailable => 'الحساب السحابي غير مفعّل';

  @override
  String get authUnavailableBody =>
      'واجهات الحساب جاهزة، لكنها تنتظر ربط خدمة المصادقة. يمكنك استخدام Wings كزائر الآن.';

  @override
  String get authContinueGuest => 'المتابعة كزائر';

  @override
  String get authValidationEmail => 'أدخل بريداً إلكترونياً صحيحاً';

  @override
  String get authValidationPassword =>
      'كلمة المرور يجب أن تكون 8 أحرف على الأقل';

  @override
  String get authValidationName => 'أدخل اسماً لا يقل عن حرفين';

  @override
  String get authValidationConfirm => 'كلمتا المرور غير متطابقتين';

  @override
  String get authAcceptTerms => 'أوافق على شروط الاستخدام وسياسة الخصوصية';

  @override
  String get authResetSent => 'إذا كان البريد مسجلاً، فسيصلك رابط الاستعادة.';

  @override
  String get profileTitle => 'الملف الشخصي';

  @override
  String get profileGuest => 'حساب الزائر';

  @override
  String get profileEdit => 'تعديل الملف';

  @override
  String get profileStats => 'إحصاءاتك';

  @override
  String get profileFavorites => 'المفضلة';

  @override
  String get profileCompleted => 'مكتمل';

  @override
  String get profileWatching => 'أشاهده';

  @override
  String get profileDownloads => 'التنزيلات';

  @override
  String get profileMemberSince => 'معنا منذ';

  @override
  String get profileSignInPrompt => 'سجّل الدخول لمزامنة مكتبتك عبر أجهزتك.';

  @override
  String get profileDeleteAccount => 'حذف الحساب';

  @override
  String get profileDeleteBody =>
      'سيتم حذف حسابك وبياناتك السحابية. بياناتك المحلية تبقى حتى تمسحها.';

  @override
  String get profileDeleteDone => 'تم حذف الحساب';

  @override
  String get notificationsTitle => 'الإشعارات';

  @override
  String get notificationsMarkAll => 'تعليم الكل كمقروء';

  @override
  String get notificationsEmpty => 'لا توجد إشعارات';

  @override
  String get notificationsSettings => 'إعدادات الإشعارات';

  @override
  String get onboardingSkip => 'تخطي';

  @override
  String get onboardingNext => 'التالي';

  @override
  String get onboardingStart => 'ابدأ الآن';

  @override
  String get onboardingTitle1 => 'اكتشف أنميك المفضل';

  @override
  String get onboardingBody1 =>
      'أحدث الحلقات، الأنمي الموسمي، والأعمال الأعلى تقييماً في مكان واحد.';

  @override
  String get onboardingTitle2 => 'شاهد بأفضل جودة';

  @override
  String get onboardingBody2 =>
      'مشغّل سريع مع اختيار الجودة والسرعة، وتذكّر موضع المشاهدة تلقائياً.';

  @override
  String get onboardingTitle3 => 'مكتبتك معك';

  @override
  String get onboardingBody3 =>
      'أضف للمفضلة، نزّل الحلقات، وتابع من حيث توقفت في أي وقت.';

  @override
  String genreTitle(String name) {
    return 'تصنيف: $name';
  }

  @override
  String get genreEmpty => 'لا توجد أعمال في هذا التصنيف';

  @override
  String get statusOngoing => 'مستمر';

  @override
  String get statusCompleted => 'مكتمل';

  @override
  String get typeSeries => 'مسلسل';

  @override
  String get typeMovie => 'فيلم';

  @override
  String get errorNoEpisodes => 'لا توجد حلقات';

  @override
  String get searchHistoryRemoved => 'حُذف من السجل';

  @override
  String get commonNext => 'التالي';

  @override
  String get commonBack => 'رجوع';

  @override
  String get authUsername => 'اسم المستخدم';

  @override
  String get authValidationUsername => '3–20 حرفاً إنجليزياً أو رقماً أو _';

  @override
  String get authCountry => 'الدولة';

  @override
  String get authChoosePhoto => 'تغيير الصورة';

  @override
  String authStepOf(String current, String total) {
    return 'الخطوة $current من $total';
  }

  @override
  String get authPasswordWeak => 'ضعيفة';

  @override
  String get authPasswordMedium => 'متوسطة';

  @override
  String get authPasswordStrong => 'قوية';

  @override
  String notificationsEpisodeBody(int number) {
    return 'الحلقة $number متاحة الآن 🎉 اضغط للمشاهدة';
  }
}
