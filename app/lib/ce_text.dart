// ---------------------------------------------------------------------------
// ایموجی‌های کاستوم (پک‌های Sticker): توکن داخل متن پیام + لینک پک
// بدون هیچ import تا همه‌جا (utils, chat_page, ...) بتونن استفاده کنن.
// ---------------------------------------------------------------------------

/// هر ایموجی کاستوم تو متن پیام به شکل  U+2063 + id + U+2063  ذخیره میشه
/// (id = حرف e + ۱۰ رقم هگز). کاراکتر U+2063 نامرئیه.
final RegExp ceRe = RegExp('\u2063(e[0-9a-f]{10})\u2063');

/// لینک اشتراک‌گذاری پک: chatapp://emoji/<id هشت‌رقمی>
final RegExp packLinkRe = RegExp(r'chatapp://emoji/([0-9a-f]{8})');

String ceToken(String id) => '\u2063$id\u2063';
String packLink(String id) => 'chatapp://emoji/$id';

/// ایموجی معمولیِ جایگزین (برای پیش‌نمایش لیست چت و ...)؛ PackStore اینو پر میکنه
String Function(String id) ceFallback = (_) => '🙂';

/// توکن‌ها رو با ایموجی معمولی عوض میکنه (برای پیش‌نمایش، کپی، نقل‌قول)
String stripCe(String s) {
  if (!s.contains('\u2063')) return s;
  return s.replaceAllMapped(ceRe, (m) => ceFallback(m.group(1)!));
}
