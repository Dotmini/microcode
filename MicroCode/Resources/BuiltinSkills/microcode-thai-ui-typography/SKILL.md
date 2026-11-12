---
name: microcode-thai-ui-typography
description: Typography, copywriting and formatting rules for interfaces and documents in Thai (and mixed Thai/English) - fonts, line height, line breaking, emphasis, numerals, Buddhist Era dates, currency, names, addresses, sorting and UI tone. Use whenever generating or reviewing Thai text, Thai UI, forms, reports or documents.
license: MIT
metadata:
  owner: MicroCode
  sources: "W3C Thai Layout Requirements (w3.org/TR/thai-lreq); Unicode Thai block; Royal Society of Thailand style usage"
---

# Thai UI and Typography

## Vertical space
Thai stacks vowels and tone marks above and below the base line. Tight boxes cut them off.
- Body line height 1.5 to 1.7. Headings no tighter than 1.3. Never `line-height: 1` on Thai.
- No fixed-height containers or `overflow: hidden` around Thai text. In SwiftUI avoid fixed `.frame(height:)` on `Text`; allow `lineLimit` with `fixedSize(horizontal: false, vertical: true)`.
- Thai looks smaller than Latin at the same point size. Set Thai about 1.1x larger when both appear (Latin 14, Thai 15 to 16). Minimum body size 14 to 16 px on the web, 13 pt in a Mac app.

## Fonts
- Modern UI, loopless: Noto Sans Thai, IBM Plex Sans Thai, Anuphan, Prompt, Kanit.
- Long reading: Noto Serif Thai, Sarabun. Thai government documents use TH Sarabun New at 16 pt.
- Declare the Thai font explicitly next to the Latin one. Relying on fallback gives mismatched baseline, size and weight in mixed lines.
- Load only the weights you use (regular, medium, bold). Thai font files are large.

## Emphasis and spacing
- No uppercase, so no all-caps labels. No true italic exists; synthetic oblique looks broken. Emphasise with weight or colour.
- No positive letter-spacing: tracking detaches tone marks from their letters.
- Put a normal space between a Latin word or number and the surrounding Thai text ("ไฟล์ 3 รายการ", "ใช้ Swift ในโปรเจกต์").

## Line breaking
- Thai has no spaces between words; breaks need dictionary segmentation. On the web set `lang="th"` and use `word-break: normal; overflow-wrap: break-word;`. Never `word-break: break-all`; it splits mid-word.
- Native text engines (Core Text, TextKit, SwiftUI) segment Thai correctly; do not insert manual breaks. Use a zero-width space (U+200B) only where an engine without segmentation must break a long fixed phrase.
- Never truncate in the middle of a Thai word; truncate at the end with an ellipsis.

## Numbers, dates, money
- Arabic digits (0 to 9) for all UI data. Thai digits only for formal print when the user asks.
- Buddhist Era is Gregorian plus 543. `Intl.DateTimeFormat("th-TH")` and `Locale(identifier: "th_TH")` default to Buddhist Era; ask explicitly for Gregorian with `th-TH-u-ca-gregory` or `Calendar(identifier: .gregorian)`. Always show the era when a date could be misread (พ.ศ. 2569 / ค.ศ. 2026).
- Currency: `฿1,234.50`, symbol first, comma thousands, dot decimal, code THB.
- Time: 24-hour in UI ("14:30 น.").

## People and places
- Name order: given name then surname. Titles: นาย, นาง, นางสาว, plus ranks and academic titles; keep titles as a separate optional field.
- National ID has 13 digits (`x-xxxx-xxxxx-xx-x`); validate the checksum, do not guess. Mobile numbers `0x-xxxx-xxxx`, international `+66`. Postal code is 5 digits.
- Address order: house no., หมู่, ซอย, ถนน, ตำบล or แขวง, อำเภอ or เขต, จังหวัด, postal code.

## Sorting and search
- Sort with locale-aware collation (`localizedStandardCompare`, `Intl.Collator("th")`); leading vowels เ แ โ ไ ใ are ignored by Thai dictionary order.
- Normalise to NFC before comparing. Do not lowercase; Thai has no case. Make tone marks optional in fuzzy search.

## Interface language
- Neutral, polite, short. Use verbs for actions: บันทึก, ยกเลิก, ลบ, ส่ง. Do not end labels with ครับ or ค่ะ; reserve particles for a deliberately conversational voice and keep one choice across the product.
- Errors say what happened and how to fix it, with no apology: "บันทึกไม่สำเร็จ: ไม่มีสิทธิ์เขียนไฟล์ ตรวจสอบสิทธิ์ของโฟลเดอร์".
- Use established Thai terms (ราชบัณฑิตยสภา) where users know them; keep common loanwords (แอป, ไฟล์, รหัสผ่าน, อีเมล). Do not transliterate every English term.
- Name an action the same way through the whole flow.

## Stress test before shipping
Render these and look for clipped marks, broken wraps and mismatched weights: `ผู้ใหญ่ปู่ฟ้าก๊วนนี้` · `น้ำที่ปั้นจั่น` · `ญี่ปุ่น ฐานทัพ` · `กรุงเทพมหานคร อัครราชทูต` · a 120-character sentence in a narrow column · a mixed line "ติดตั้ง Xcode 26 แล้ว 3 รายการ".
