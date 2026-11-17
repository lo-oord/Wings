import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/errors/app_failure.dart';
import '../../core/utils/tr.dart';

/// Maps authentication failures to clear Arabic/English copy.
///
/// Error codes stay in [AppFailure.technical] so the UI never has to parse an
/// exception message.
String authErrorText(BuildContext context, Object error) {
  if (error is GoogleSignInException) {
    if (error.code == GoogleSignInExceptionCode.canceled) {
      return Tr.of(
        context,
        ar: 'تم إلغاء تسجيل الدخول بجوجل.',
        en: 'Google sign-in was cancelled.',
      );
    }
    if (error.code == GoogleSignInExceptionCode.providerConfigurationError ||
        error.code == GoogleSignInExceptionCode.clientConfigurationError) {
      return Tr.of(
        context,
        ar: 'خدمة تسجيل الدخول بجوجل غير مهيأة على هذا الجهاز. تحقق من إعدادات Firebase.',
        en: 'Google sign-in is not configured on this device. Check the Firebase settings.',
      );
    }
    return Tr.of(
      context,
      ar: 'تعذر تسجيل الدخول بجوجل. حاول مرة أخرى.',
      en: 'Google sign-in failed. Please try again.',
    );
  }

  if (error is FirebaseAuthException) {
    final text = _byCode(context, error.code);
    if (text != null) return text;
    return _generic(context);
  }

  // Firestore failures (profile, username reservation, avatar bytes) arrive as
  // plain FirebaseException; a rejected write is almost always a rules or
  // setup problem, which the generic message would hide.
  if (error is FirebaseException) {
    final text = _byCode(context, error.code);
    if (text != null) return text;
    return _generic(context);
  }

  if (error is AppFailure) {
    final code = error.technical;
    if (code != null) {
      final text = _byCode(context, code);
      if (text != null) return text;
    }
    if (error.kind == FailureKind.cancelled) {
      return Tr.of(
        context,
        ar: 'تم إلغاء العملية.',
        en: 'The action was cancelled.',
      );
    }
    if (error.kind == FailureKind.network) {
      return Tr.of(
        context,
        ar: 'لا يوجد اتصال بالإنترنت. تحقق من الشبكة وحاول مرة أخرى.',
        en: 'No internet connection. Check your network and try again.',
      );
    }
    return _generic(context);
  }

  return _generic(context);
}

String _generic(BuildContext context) => Tr.of(
  context,
  ar: 'حدث خطأ غير متوقع. حاول مرة أخرى.',
  en: 'Something went wrong. Please try again.',
);

String? _byCode(BuildContext context, String code) => switch (code) {
  'invalid-email' => Tr.of(
    context,
    ar: 'البريد الإلكتروني غير صالح.',
    en: 'That email address is not valid.',
  ),
  'user-not-found' || 'invalid-credential' || 'wrong-password' => Tr.of(
    context,
    ar: 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
    en: 'The email or password is incorrect.',
  ),
  'user-disabled' => Tr.of(
    context,
    ar: 'تم تعطيل هذا الحساب. تواصل مع الدعم.',
    en: 'This account has been disabled. Please contact support.',
  ),
  'email-already-in-use' => Tr.of(
    context,
    ar: 'هذا البريد الإلكتروني مسجل مسبقًا. سجّل الدخول بدلًا من إنشاء حساب.',
    en: 'This email is already registered. Sign in instead.',
  ),
  'weak-password' => Tr.of(
    context,
    ar: 'كلمة المرور ضعيفة. استخدم 8 أحرف على الأقل مع أرقام وحروف.',
    en: 'That password is too weak. Use at least 8 characters with letters and numbers.',
  ),
  'too-many-requests' => Tr.of(
    context,
    ar: 'محاولات كثيرة. انتظر قليلًا ثم حاول مرة أخرى.',
    en: 'Too many attempts. Please wait a moment and try again.',
  ),
  'network-request-failed' => Tr.of(
    context,
    ar: 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.',
    en: 'Could not reach the server. Check your connection and try again.',
  ),
  'operation-not-allowed' => Tr.of(
    context,
    ar: 'طريقة تسجيل الدخول هذه غير مفعّلة حاليًا.',
    en: 'This sign-in method is not enabled.',
  ),
  'requires-recent-login' => Tr.of(
    context,
    ar: 'لأمان حسابك، أعد تسجيل الدخول ثم كرر العملية.',
    en: 'For your security, sign in again and retry.',
  ),
  'account-exists-with-different-credential' => Tr.of(
    context,
    ar: 'هذا البريد مسجل بطريقة دخول أخرى. سجّل الدخول بها ثم اربط جوجل من الإعدادات.',
    en: 'This email uses another sign-in method. Sign in with it, then link Google from settings.',
  ),
  'credential-already-in-use' => Tr.of(
    context,
    ar: 'حساب جوجل هذا مرتبط بحساب آخر بالفعل.',
    en: 'That Google account is already linked to another account.',
  ),
  'provider-already-linked' => Tr.of(
    context,
    ar: 'حساب جوجل مرتبط بحسابك بالفعل.',
    en: 'Google is already linked to your account.',
  ),
  'password-required' => Tr.of(
    context,
    ar: 'أدخل كلمة المرور الحالية للتأكيد.',
    en: 'Enter your current password to confirm.',
  ),
  'missing-google-id-token' => Tr.of(
    context,
    ar: 'لم يصل رمز جوجل. تحقق من تهيئة Firebase وSHA لجهاز التوقيع.',
    en: 'Google returned no token. Check your Firebase Android app and signing SHA.',
  ),
  'google-clientConfigurationError' ||
  'google-providerConfigurationError' => Tr.of(
    context,
    ar: 'تسجيل الدخول بجوجل غير مهيأ. أضف SHA-1 وSHA-256 في Firebase.',
    en: 'Google sign-in is misconfigured. Add the SHA-1 and SHA-256 in Firebase.',
  ),
  'google-canceled' => Tr.of(
    context,
    ar: 'تم إلغاء تسجيل الدخول بجوجل.',
    en: 'Google sign-in was cancelled.',
  ),
  'google-unsupported-platform' => Tr.of(
    context,
    ar: 'تسجيل الدخول بجوجل غير مدعوم على هذا الجهاز.',
    en: 'Google sign-in is not supported on this device.',
  ),
  'permission-denied' => Tr.of(
    context,
    ar: 'رفض الخادم العملية. تأكد من نشر قواعد Firestore الجديدة وأن الحساب مسجّل الدخول.',
    en: 'The server rejected the operation. Publish the latest Firestore rules and make sure you are signed in.',
  ),
  'unavailable' || 'deadline-exceeded' => Tr.of(
    context,
    ar: 'تعذر الوصول إلى قاعدة البيانات. تحقق من الإنترنت وحاول مرة أخرى.',
    en: 'Could not reach the database. Check your connection and try again.',
  ),
  'not-found' => Tr.of(
    context,
    ar: 'قاعدة البيانات غير موجودة. أنشئ Cloud Firestore من لوحة Firebase.',
    en: 'The database does not exist. Create Cloud Firestore in the Firebase console.',
  ),
  'invalid-api-key' ||
  'api-key-not-valid' ||
  'app-not-authorized' ||
  'unauthorized-domain' => Tr.of(
    context,
    ar: 'إعدادات Firebase لهذا التطبيق غير صحيحة. راجع google-services.json.',
    en: 'This app\'s Firebase configuration is invalid. Check google-services.json.',
  ),
  'internal-error' => Tr.of(
    context,
    ar: 'خطأ داخلي من Firebase. حاول مرة أخرى بعد قليل.',
    en: 'Firebase returned an internal error. Try again shortly.',
  ),
  'username-taken' => Tr.of(
    context,
    ar: 'اسم المستخدم هذا محجوز الآن. اختر اسمًا آخر.',
    en: 'That username is taken. Pick another one.',
  ),
  'username-invalid' => Tr.of(
    context,
    ar: 'اسم المستخدم غير صالح. استخدم 3–20 حرفًا إنجليزيًا أو رقمًا أو _.',
    en: 'Invalid username. Use 3–20 English letters, numbers or underscores.',
  ),
  'username-unavailable' => Tr.of(
    context,
    ar: 'تعذر إيجاد اسم مستخدم متاح. حاول مرة أخرى.',
    en: 'Could not find an available username. Please try again.',
  ),
  'avatar-too-large' => Tr.of(
    context,
    ar: 'الصورة كبيرة جدًا. اختر صورة أخرى.',
    en: 'That picture is too large. Choose another one.',
  ),
  'cover-too-large' => Tr.of(
    context,
    ar: 'صورة الغلاف كبيرة جدًا أو غير قابلة للقراءة. اختر صورة أخرى.',
    en: 'That cover is too large or cannot be read. Choose another image.',
  ),
  'comment-too-fast' => Tr.of(
    context,
    ar: 'انتظر لحظات قبل إرسال تعليق آخر.',
    en: 'Wait a moment before posting another comment.',
  ),
  'delete-rules' => Tr.of(
    context,
    ar: 'مُنع حذف بياناتك من الخادم. انشر أحدث قواعد Firestore ثم أعد المحاولة، وستبقى بياناتك سليمة حتى تكتمل العملية.',
    en: 'The server blocked the deletion. Publish the latest Firestore rules and retry; your data stays intact until it completes.',
  ),
  'no-profile' => Tr.of(
    context,
    ar: 'لم يتم تحميل ملفك الشخصي بعد. حاول بعد لحظة.',
    en: 'Your profile is not loaded yet. Try again in a moment.',
  ),
  'no-user' => Tr.of(
    context,
    ar: 'انتهت الجلسة. سجّل الدخول من جديد.',
    en: 'The session ended. Please sign in again.',
  ),
  _ => null,
};
