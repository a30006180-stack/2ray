# GHTUN — GitHub Codespace VPN

## ⚡ کاهش پینگ — راهنما

### 🗺️ مهم‌ترین فاکتور: انتخاب Region

پینگ از ایران به region های مختلف:

| Region | پینگ تقریبی از ایران |
|--------|----------------------|
| **West Europe** 🇳🇱 (بهترین) | ~80–120 ms |
| Southeast Asia 🇸🇬 | ~120–180 ms |
| West US 2 🇺🇸 | ~180–230 ms |
| **East US** 🇺🇸 (پیش‌فرض — بدترین) | ~200–280 ms |

### روش انتخاب Region صحیح

**از GitHub CLI:**
```bash
gh codespace create --repo <your-username>/<repo-name> --location WestEurope
```

**از وب:**
1. برو به [github.com/codespaces](https://github.com/codespaces)
2. روی **New codespace** کلیک کن
3. مخزن خودت رو انتخاب کن
4. گزینه **Region** رو روی **West Europe** بذار

---

## 🚀 اجرای Codespace

بعد از باز شدن Codespace، اسکریپت به صورت خودکار اجرا میشه و:

1. UUID جدید تولید می‌کنه
2. بهترین CDN IP رو با ping scan پیدا می‌کنه
3. کانفیگ VLESS آماده استفاده بهت میده

## 📌 نکات پینگ

- **کانفیگ CDN** (با IP عددی) معمولاً پینگ کمتری داره — **اول این رو امتحان کن**
- **کانفیگ Direct** (با domain) backup هست
- پینگ نهایی = فاصله فیزیکی + overhead پروکسی GitHub (~80ms)
- با West Europe region انتظار **120–200ms** داری
