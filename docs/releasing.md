# إصدار جديد من Wings

كل ما يلي يتم داخل GitHub Actions فقط؛ لا يوجد بناء محلي.

## الخطوات

1. **ارفع رقم الإصدار** في `pubspec.yaml` (`version: 1.0.1+2`).
2. **حدّث ملاحظات الإصدار**:
   - `site/updates/latest.json`: عدّل `notes_ar` و`notes_en` و`welcome` (واترك الروابط، السكربت يكتبها).
   - `docs/release-notes/v<version>.md` إن رغبت بسجل إضافي.
   - `site/changelog.html`: أضف بطاقة الإصدار الجديد.
3. **ادفع إلى `main`** → workflow `Flutter CI` يبني ويختبر ويحزم.

## ما يفعله الـ workflow

- يبني `flutter build apk --release --split-per-abi` (arm64-v8a، armeabi-v7a، x86_64)
  و`flutter build apk --release` (universal) و`flutter build appbundle`.
- يشغّل `python3 tools/site_release.py`:
  - ينسخ الحزم الأربع إلى `site/downloads/v<version>/`.
  - يعيد تنزيل حزم الإصدارات السابقة من الموقع الحي حتى تبقى متاحة (نشر Vercel لقطة).
  - يحدّث `site/downloads/index.json` وروابط `site/updates/latest.json`.
- ينشر `site/` إلى Vercel (project `wingsapp`) باستخدام `VERCEL_TOKEN`.

## المتطلبات في المستودع

| Name | النوع | الغرض |
| --- | --- | --- |
| `VERCEL_TOKEN` | Secret | نشر الموقع والحزم إلى Vercel |
| `ANDROID_KEYSTORE_BASE64` | Secret | توقيع الحزم (بدونه توقيع debug) |
| `ANDROID_KEYSTORE_PASSWORD` | Secret | كلمة مرور الـ keystore |
| `ANDROID_KEY_ALIAS` | Secret | اسم المفتاح |
| `ANDROID_KEY_PASSWORD` | Secret | كلمة مرور المفتاح |

`VERCEL_ORG_ID` و`VERCEL_PROJECT_ID` مكتوبان داخل الـ workflow لأنهما معرّفان عامّان لا أسرار.

## التحقق بعد النشر

- `https://wingsapp.vercel.app/download` يعرض الحزم الأربع.
- `https://wingsapp.vercel.app/downloads/v<version>/wings-<version>-arm64-v8a.apk` يعيد `200`.
- `https://wingsapp.vercel.app/downloads/index.json` يحتوي الإصدار الجديد والإصدارات السابقة.
- `https://wingsapp.vercel.app/updates/latest.json` يحمل `version` و`build` الجديدين و`apk_urls`.
- نافذة التحديث داخل التطبيق تظهر لكل من نسخته أقدم من `build` الجديد.
