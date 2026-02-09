# SwitchFix for macOS — Claude Code Implementation Prompt (Ralph Method)

> **Методологія**: Ralph (автономна покрокова імплементація з верифікацією кожного milestone)
> **Агент**: Claude Code (CLI)
> **Мова проєкту**: Swift 5.9+
> **Платформа**: macOS 13.0+ (Ventura), Apple Silicon native (ARM64)

---

## ПРЕАМБУЛА ДЛЯ АГЕНТА

Ти — senior macOS system developer з 15+ роками досвіду розробки нативних Apple-додатків, input methods і system-level utilities. Ти створюєш **SwitchFix** — легковагу утиліту для macOS, яка автоматично визначає неправильну розкладку клавіатури (кирилиця замість латиниці і навпаки) та коригує введений текст.

### Принципи роботи за методом Ralph

1. **Повністю автономна імплементація** — ти пишеш весь код самостійно, без участі людини
2. **Покрокове виконання з верифікацією** — після кожного milestone компілюєш, тестуєш, фіксиш помилки
3. **Ніколи не переходь до наступного milestone, поки поточний не компілюється і не працює**
4. **Кожен файл пишеш повністю** — ніяких плейсхолдерів, TODO, або пропущеного коду
5. **Після кожного milestone** — запускай `swift build` та unit тести, верифікуй результат
6. **Якщо помилка компіляції** — фікси її негайно, не рухайся далі
7. **Коміть після кожного успішного milestone** з осмисленим повідомленням

---

## АРХІТЕКТУРА ПРОЄКТУ

### Високорівнева структура

```
SwitchFix/
├── Package.swift
├── Sources/
│   ├── SwitchFixApp/          # Main entry point (menu bar app)
│   │   └── main.swift
│   ├── Core/                        # Core business logic
│   │   ├── KeyboardMonitor.swift    # CGEventTap + keyboard event capture
│   │   ├── LayoutDetector.swift     # Language detection engine
│   │   ├── TextCorrector.swift      # Text replacement logic
│   │   ├── LayoutMapper.swift       # Character mapping between layouts
│   │   └── InputSourceManager.swift # macOS Input Source switching
│   ├── Dictionary/                  # Language dictionaries & validation
│   │   ├── WordValidator.swift      # Dictionary lookup interface
│   │   ├── BloomFilter.swift        # Probabilistic word existence check
│   │   └── DictionaryLoader.swift   # Lazy dictionary loading from bundle
│   ├── UI/                          # Menu bar UI
│   │   ├── StatusBarController.swift # NSStatusItem management
│   │   └── PreferencesManager.swift  # UserDefaults-based settings
│   └── Utils/                       # Helpers
│       ├── Permissions.swift        # Accessibility permission checks
│       ├── KeyCodeMapping.swift     # Virtual key code → character tables
│       └── AppFilter.swift          # Per-app enable/disable logic
├── Resources/
│   ├── Dictionaries/               # Compact word lists (.txt, loaded lazily)
│   │   ├── en_US.txt               # English dictionary (~50K common words)
│   │   ├── uk_UA.txt               # Ukrainian dictionary (~40K common words)
│   │   └── ru_RU.txt               # Russian dictionary (~50K common words)
│   ├── Assets.xcassets/            # Menu bar icons (light/dark)
│   └── Info.plist
└── Tests/
    └── SwitchFixTests/
        ├── LayoutMapperTests.swift
        ├── BloomFilterTests.swift
        ├── LayoutDetectorTests.swift
        └── WordValidatorTests.swift
```

### Компонентна діаграма (текстова)

```
┌─────────────────────────────────────────────────────┐
│                   macOS System                       │
│  ┌──────────────┐    ┌─────────────────────────┐    │
│  │ CGEventTap   │───▶│   KeyboardMonitor       │    │
│  │ (HID Events) │    │   - captures keystrokes  │    │
│  └──────────────┘    │   - filters modifiers     │    │
│                      │   - ignores passwords     │    │
│                      └──────────┬────────────────┘    │
│                                 │                     │
│                                 ▼                     │
│                      ┌─────────────────────────┐     │
│                      │   LayoutDetector         │     │
│                      │   - buffers characters    │     │
│                      │   - queries WordValidator │     │
│                      │   - decides: correct or   │     │
│                      │     wrong layout?         │     │
│                      └──────────┬────────────────┘     │
│                                 │                     │
│                      ┌──────────▼────────────────┐    │
│                      │   TextCorrector           │    │
│                      │   - maps chars via         │    │
│                      │     LayoutMapper           │    │
│                      │   - deletes wrong text     │    │
│                      │   - types correct text     │    │
│                      │   - via CGEvent posting    │    │
│                      └──────────┬────────────────┘    │
│                                 │                     │
│                      ┌──────────▼────────────────┐    │
│                      │   InputSourceManager      │    │
│                      │   - switches layout via    │    │
│                      │     TISSelectInputSource   │    │
│                      └───────────────────────────┘    │
│                                                       │
│  ┌──────────────────────────────────────────────┐    │
│  │  StatusBarController (NSStatusItem)           │    │
│  │  - on/off toggle, settings, quit              │    │
│  └──────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────┘
```

### Потік даних (Data Flow)

1. **CGEventTap** перехоплює keyDown події системного рівня
2. **KeyboardMonitor** фільтрує: ігнорує modifier keys, функціональні клавіші, password fields
3. Символ додається в **буфер поточного слова** (очищується при пробілі/Enter/Tab)
4. Після накопичення 3–4 символів **LayoutDetector** запитує **WordValidator**
5. **WordValidator** перевіряє слово через **BloomFilter** + fallback exact lookup
6. Якщо слово не валідне в поточній розкладці — **LayoutMapper** конвертує символи в альтернативну розкладку
7. Конвертоване слово перевіряється у словнику альтернативної мови
8. Якщо валідне — **TextCorrector** видаляє набрані символи (емуляція backspace через CGEvent) і вводить правильні
9. **InputSourceManager** перемикає розкладку через TIS API

---

## MILESTONE ПЛАН ІМПЛЕМЕНТАЦІЇ

### MILESTONE 0: Project Scaffolding

**Мета**: Створити Swift Package з правильною структурою, переконатися що `swift build` проходить.

**Дії**:
- Ініціалізувати `Package.swift` як executable з targets: `SwitchFixApp` (executable), `Core`, `Dictionary`, `UI`, `Utils`
- Створити мінімальний `main.swift` з `NSApplication` setup для menu bar app (LSUIElement = true — без Dock icon)
- Створити порожні файли для кожного модуля з мінімальними stub-класами
- Platform: `.macOS(.v13)`
- Не використовувати SwiftUI для основного UI — використовувати AppKit (NSStatusItem, NSMenu) для мінімального RAM footprint

**Верифікація**: `swift build` проходить без помилок. Додаток запускається і одразу завершується (без UI поки що).

---

### MILESTONE 1: Menu Bar Icon та Basic App Lifecycle

**Мета**: Додаток з'являється в menu bar, показує іконку, має меню з Enable/Disable та Quit.

**Дії**:
- Імплементувати `StatusBarController` з NSStatusItem
- Іконка: використати SF Symbols (`keyboard`) або створити простий NSImage programmatically (два символи "Ab/Ук" через NSAttributedString rendering в NSImage)
- Dropdown menu: "Enable/Disable" toggle, separator, "Launch at Login" toggle, separator, "Quit"
- Імплементувати `PreferencesManager` на базі UserDefaults для збереження стану enable/disable та launch-at-login
- Launch at Login через SMAppService (macOS 13+) або LSSharedFileList fallback
- App lifecycle: NSApplication.shared з delegate, без window, LSUIElement = true

**Верифікація**: Додаток запускається, показує іконку в menu bar, меню працює, Quit завершує процес. `swift build && swift run` працює.

---

### MILESTONE 2: Accessibility Permissions та CGEventTap

**Мета**: Запит Accessibility permissions, створення CGEventTap для перехоплення клавіатурних подій.

**Дії**:
- Імплементувати `Permissions.swift`:
  - Перевірка `AXIsProcessTrusted()` при старті
  - Якщо немає доступу — показати alert з кнопкою "Open System Preferences" (прямий deep link до Privacy → Accessibility)
  - Повторна перевірка через polling (кожні 2 секунди) після відкриття Settings
- Імплементувати `KeyboardMonitor.swift`:
  - Створення CGEventTap з mask `.keyDown` (тільки keyDown, не keyUp)
  - Event tap тип: `.cgSessionEventTap` (session-level, не потрібен root)
  - Callback обробляє event і передає keyCode + characters в LayoutDetector
  - Фільтрація: ігнорувати events з modifier flags (Cmd, Ctrl, Option — крім Shift)
  - Фільтрація: ігнорувати функціональні клавіші (F1-F12, Escape, arrows, etc.)
  - Run loop integration: додати CGEventTap source до CFRunLoop
- Визначення активного додатка через NSWorkspace.shared.frontmostApplication
- Password field detection: перевірка AXUIElement focused element на `AXIsSecure` attribute

**Критично**: CGEventTap callback має бути C-convention (@convention(c)), не closure. Використовувати Unmanaged pointer для передачі context (self) у callback.

**Верифікація**: Додаток запитує Accessibility permission. Після надання — в консолі логуються keystroke events (тільки для debug, далі логування буде видалено). Password fields ігноруються.

---

### MILESTONE 3: Layout Mapping Engine

**Мета**: Повна таблиця маппінгу символів між розкладками QWERTY ↔ Ukrainian ↔ Russian.

**Дії**:
- Імплементувати `LayoutMapper.swift`:
  - Двонаправлені маппінги: EN→UK, UK→EN, EN→RU, RU→EN, UK→RU, RU→UK
  - Маппінг на рівні символів (character-to-character), не keyCode
  - Таблиця включає: всі літери (lower + upper case), цифри (однакові), розділові знаки (різні положення на клавіатурі)
  - Спеціальні випадки: `'` (EN) → `є` (UK) / `э` (RU), `[` → `х`, `]` → `ї`/`ъ`, etc.
  - Повна таблиця для стандартних macOS розкладок: "U.S.", "Ukrainian", "Russian"
- Імплементувати `KeyCodeMapping.swift`:
  - Virtual keyCode → character mapping для кожної розкладки
  - Використовувати UCKeyTranslate або TISGetInputSourceProperty для динамічного маппінгу (більш надійно ніж hardcoded таблиці)
  - Fallback: hardcoded таблиці якщо dynamic mapping недоступний
- Функція конвертації: `convert(text: String, from: Layout, to: Layout) -> String`
- Layout enum: `.english`, `.ukrainian`, `.russian`

**Верифікація**: Unit тести — конвертація "ghbdtn" → "привет" (EN→RU), "руддщ" → "hello" (RU→EN), "пшерги" → "github" (UK→EN). Всі тести проходять.

---

### MILESTONE 4: Dictionary System з Bloom Filter

**Мета**: Компактні словники для EN/UK/RU з швидкою валідацією слів через Bloom Filter.

**Дії**:
- Імплементувати `BloomFilter.swift`:
  - Generic Bloom filter з конфігурованим розміром біт-масиву та кількістю хеш-функцій
  - Хеш-функції: використовувати FNV-1a або MurmurHash3 (імплементувати в Swift, без зовнішніх залежностей)
  - Параметри: для 50K слів — розмір ~600KB (false positive rate ~1%), 7 hash functions
  - Методи: `insert(_ word: String)`, `mightContain(_ word: String) -> Bool`
  - Серіалізація: збереження/завантаження біт-масиву як Data (для pre-built dictionaries)
- Імплементувати `DictionaryLoader.swift`:
  - Lazy loading: словники завантажуються тільки при першому зверненні до відповідної мови
  - Формат словника: plain text, одне слово на рядок, lowercase
  - При завантаженні: читати файл рядок за рядком (не цілий файл в пам'ять), вставляти в BloomFilter
  - Зберігати тільки BloomFilter в RAM, не список слів
  - Estimated RAM per dictionary: ~600KB (BloomFilter) замість ~2-5MB (word list)
- Імплементувати `WordValidator.swift`:
  - `isValidWord(_ word: String, language: Language) -> Bool`
  - Нормалізація: lowercase, trim whitespace
  - Short word bypass: слова ≤ 2 символи — ігнорувати (занадто багато false positives)
  - Common patterns bypass: числа, URLs (починаються з http/www), email patterns, camelCase
- Підготувати словники:
  - English: ~50K найчастіших слів (можна згенерувати compact list)
  - Ukrainian: ~40K слів
  - Russian: ~50K слів
  - Формат: один файл .txt на мову, включений в Resources/Dictionaries/

**Критично щодо словників**: Оскільки Claude Code не має доступу до інтернету, словники потрібно згенерувати програмно. Створити Swift script який генерує базові словники з:
- Найпоширеніших слів кожної мови (hardcoded масиви з top-1000-5000 слів)
- Автоматичної генерації словоформ (для UK/RU — базові відмінки, множина)
- Збереження у .txt файли

**Альтернатива**: Якщо генерація повних словників занадто об'ємна — почати з compact словників (1000-3000 слів на мову) і задокументувати як користувач може замінити їх на повніші.

**Верифікація**: Unit тести — BloomFilter вставка/перевірка працює, false positive rate < 2%. WordValidator коректно валідує "hello" (EN), "привіт" (UK), "привет" (RU), і коректно відхиляє "ghbdtn" (EN), "руддщ" (RU).

---

### MILESTONE 5: Layout Detection Engine

**Мета**: Інтелектуальне визначення чи поточний текст набирається в неправильній розкладці.

**Дії**:
- Імплементувати `LayoutDetector.swift`:
  - Word buffer: накопичує символи поточного слова
  - Buffer flush: при пробілі, Enter, Tab, Escape, або при зміні фокусу додатка
  - Detection trigger: після накопичення N символів (конфігуровано, default = 3)
  - Алгоритм detection:
    1. Отримати поточну активну розкладку через `TISCopyCurrentKeyboardInputSource`
    2. Перевірити буфер як слово поточної мови через WordValidator
    3. Якщо не валідне — конвертувати через LayoutMapper в усі альтернативні розкладки
    4. Перевірити конвертовані варіанти через WordValidator
    5. Якщо один з варіантів валідний — повернути (target_layout, converted_word)
    6. Якщо жоден не валідний — не робити нічого (невідоме слово, можливо технічний термін)
  - Confidence scoring: якщо BloomFilter каже "might contain" — це не 100% certainty
  - Consecutive detection: для підвищення accuracy — вимагати 2 слова підряд в "неправильній" розкладці перед корекцією (конфігуровано)
  - State machine:
    - `idle` — чекає на keystroke
    - `buffering` — накопичує символи
    - `detecting` — аналізує буфер
    - `correcting` — виконує корекцію (блокує нові events)
    - `cooldown` — короткий cooldown після корекції

**Верифікація**: Unit тести з mock WordValidator — подача буферу "ghbdtn" при активній EN розкладці повертає (.russian, "привет"). Подача "привіт" при активній UK розкладці повертає nil (слово валідне).

---

### MILESTONE 6: Text Correction Engine

**Мета**: Видалення неправильного тексту і введення правильного через CGEvent emulation.

**Дії**:
- Імплементувати `TextCorrector.swift`:
  - Correction flow:
    1. Отримати кількість символів для видалення (довжина буфера)
    2. Згенерувати N подій CGEvent keyDown/keyUp для backspace (keyCode 51)
    3. Перемкнути розкладку через InputSourceManager
    4. Згенерувати CGEvent для кожного символу правильного слова
    5. Відновити курсор якщо потрібно
  - CGEvent generation:
    - Використовувати `CGEvent(keyboardEventSource:virtualKey:keyDown:)` для backspace
    - Для введення символів: використовувати `CGEvent.keyboardSetUnicodeString` замість keyCode mapping (працює незалежно від розкладки)
    - Event posting: `event.post(tap: .cgAnnotatedSessionEventTap)`
  - Timing:
    - Мінімальна затримка між events: використовувати `usleep` або DispatchQueue з мікро-затримками
    - Загальний час корекції одного слова (5-10 символів): < 50ms
  - Safety:
    - Disable event tap monitoring під час корекції (щоб не ловити свої ж events)
    - Undo support: зберегти оригінальний текст, щоб Cmd+Z працював нативно через app's undo stack
    - Rollback якщо correction fails (наприклад, app втратив фокус)
- Імплементувати `InputSourceManager.swift`:
  - `currentLayout() -> Layout`: отримати поточну розкладку через TISCopyCurrentKeyboardInputSource
  - `switchTo(_ layout: Layout)`: перемкнути через TISSelectInputSource
  - Layout identification: порівняння `kTISPropertyInputSourceID` з відомими ID:
    - "com.apple.keylayout.US" → .english
    - "com.apple.keylayout.Ukrainian" → .ukrainian
    - "com.apple.keylayout.Russian" → .russian
  - Enumerate available layouts: TISCreateInputSourceList для визначення встановлених розкладок

**Верифікація**: Integration test — у TextEdit набрати "ghbdtn", тригернути корекцію, текст замінюється на "привет" і розкладка перемикається на Russian. Тест ручний (через запуск додатку).

---

### MILESTONE 7: Hotkey-Triggered Correction Mode

**Мета**: Альтернативний режим — корекція по гарячій клавіші замість автоматичної.

**Дії**:
- Додати hotkey monitoring в KeyboardMonitor:
  - Default hotkey: Ctrl+Shift+Space (конфігуровано)
  - Hotkey detection через CGEventTap modifier flags
  - При натисканні hotkey — негайно конвертувати поточне слово (весь буфер)
- Додати в PreferencesManager:
  - `correctionMode`: `.automatic` або `.hotkey`
  - `hotkeyModifiers`: набір модифікаторів
  - `hotkeyKeyCode`: virtual keyCode
- Режим `.hotkey`:
  - Буфер накопичує символи як зазвичай
  - Detection НЕ запускається автоматично
  - При hotkey — виконати detection + correction для поточного буфера
  - Також підтримати selection-based correction: якщо є виділений текст — конвертувати його
- Selection-based correction:
  - Отримати виділений текст через AXUIElement → AXSelectedText
  - Конвертувати через LayoutMapper
  - Замінити через Cmd+V (clipboard) або через CGEvent keystroke emulation
  - Відновити clipboard після заміни

**Верифікація**: Набрати "ghbdtn" в TextEdit, натиснути Ctrl+Shift+Space — текст замінюється на "привет".

---

### MILESTONE 8: Application Filtering та Edge Cases

**Мета**: Per-app enable/disable, обробка edge cases.

**Дії**:
- Імплементувати `AppFilter.swift`:
  - Blacklist mode: список bundle ID додатків де корекція вимкнена
  - Default blacklist: Terminal.app, iTerm2, всі IDE (Xcode, VS Code, JetBrains), password managers
  - UI для додавання/видалення додатків з blacklist (через menu bar submenu)
  - Detection активного додатка: NSWorkspace.shared.frontmostApplication.bundleIdentifier
- Edge cases handling в KeyboardMonitor:
  - Password fields: перевірка AXSecureTextField через Accessibility API
  - Keyboard shortcuts: ігнорувати будь-які events з Cmd, Ctrl, Option (крім Shift)
  - Rapid typing: debounce detection — не запускати detection частіше ніж кожні 100ms
  - Mixed language: якщо в буфері є і кириличні і латинські символи — не коригувати
  - URLs та email: regex-based detection, skip correction
  - Numbers та special chars: не включати в буфер для валідації, але зберігати позицію
  - Punctuation: flush buffer при розділових знаках (`.`, `,`, `:`, `;`, `!`, `?`)
- Undo підтримка:
  - Перед корекцією — скопіювати оригінальний текст в internal undo stack
  - Hotkey для undo корекції: Ctrl+Z або custom hotkey
  - Один рівень undo достатньо

**Верифікація**: Перевірити що корекція НЕ працює в Terminal, НЕ спрацьовує на URLs, НЕ спрацьовує в password fields.

---

### MILESTONE 9: Performance Optimization та Memory Management

**Мета**: Довести RAM < 20MB, latency < 100ms, battery efficiency.

**Дії**:
- Memory optimization:
  - Профілювання через Instruments (Allocations, Leaks)
  - Переконатися що BloomFilter використовує compact Data (UInt8 array), не Set
  - Lazy loading: словник завантажується тільки коли відповідна розкладка вперше детектується
  - Weak references де можливо
  - No retain cycles в closures (explicit [weak self])
- Performance:
  - CGEventTap callback: мінімум роботи в callback, dispatch async на background queue
  - BloomFilter lookup: O(k) де k = кількість хешів (~7), дуже швидко
  - String conversion: використовувати utf8 view замість Character iteration де можливо
  - Buffer: pre-allocated, максимальний розмір 50 символів, circular buffer pattern
- Battery:
  - Event tap автоматично деактивується коли system goes to sleep
  - Не використовувати таймери або polling (крім permission check)
  - Мінімальне CPU usage: event-driven архітектура
- Measurement:
  - Додати internal timing для detection cycle (debug mode only)
  - Target: < 5ms для BloomFilter lookup, < 50ms для повного correction cycle

**Верифікація**: `swift build -c release`, запустити, перевірити в Activity Monitor: RSS < 20MB, CPU ~0% в idle.

---

### MILESTONE 10: Polish, Distribution та Final Testing

**Мета**: App bundle, code signing, UI polish, comprehensive testing.

**Дії**:
- UI polish:
  - Menu bar icon: підтримка light/dark mode (template image)
  - Subtle notification при корекції (optional): зникаюча підказка біля cursor
  - Settings у dropdown: correction mode toggle, app blacklist, launch at login
- Distribution:
  - Створити .app bundle structure
  - Info.plist: LSUIElement = true, minimum OS version, bundle ID
  - Code signing: ad-hoc signing для локального використання
  - Notarization: задокументувати процес (потребує Apple Developer account)
  - DMG creation script або простий zip для розповсюдження
- Final testing checklist:
  - [ ] Запуск і відображення в menu bar
  - [ ] Accessibility permission request
  - [ ] Автокорекція EN→RU в TextEdit
  - [ ] Автокорекція EN→UK в TextEdit
  - [ ] Автокорекція RU→EN в Safari address bar
  - [ ] Hotkey корекція працює
  - [ ] Password fields ігноруються
  - [ ] Terminal ігнорується
  - [ ] Швидкий набір не ламає корекцію
  - [ ] RAM < 20MB
  - [ ] Quit працює чисто
  - [ ] Launch at Login працює
  - [ ] Light/dark mode іконка коректна

**Верифікація**: Повний прогін чеклісту. Всі пункти пройдені.

---

## КРИТИЧНІ ТЕХНІЧНІ РІШЕННЯ

### Чому CGEventTap, а не NSEvent.addGlobalMonitorForEvents

- CGEventTap дає доступ до raw keyCode ДО обробки Input Source
- Дозволяє блокувати/модифікувати events (passive tap — тільки читання, active — модифікація)
- Для цього проєкту: **passive tap** достатньо (ми не модифікуємо keystroke, а постфактум виправляємо)
- NSEvent global monitor не дає keyCode, тільки characters (вже оброблені Input Source)

### Чому BloomFilter, а не HashSet

- HashSet<String> для 50K слів ≈ 3-5MB RAM
- BloomFilter для 50K слів ≈ 600KB RAM (при 1% false positive rate)
- False positives прийнятні: worst case — слово не буде виправлено (пропущена корекція краще за хибну)
- False negatives неможливі (if word is in dictionary, BloomFilter always returns true)

### Чому Swift Package Manager, а не Xcode Project

- Claude Code працює в terminal — SPM повністю CLI-based
- `swift build`, `swift test`, `swift run` без Xcode
- Простіша структура, менше boilerplate
- Для .app bundle — фінальний скрипт пакування

### Чому AppKit, а не SwiftUI

- SwiftUI для menu bar app = overhead (додатковий framework loading)
- NSStatusItem + NSMenu — мінімальний RAM footprint
- Більш передбачувана поведінка для system-level utility
- macOS 13 SwiftUI MenuBarExtra має відомі баги з lifecycle

### Privacy: Що НЕ зберігається

- Keystroke events: обробляються в пам'яті, не логуються, не пишуться на диск
- Word buffer: очищується після кожного detection cycle
- Correction history: не зберігається
- На диск пишуться ТІЛЬКИ: enabled/disabled state, correction mode, app blacklist, hotkey config (через UserDefaults)

---

## ІНСТРУКЦІЇ ДЛЯ CLAUDE CODE АГЕНТА

### Перед початком роботи

1. Ти вже знаходишся в дерикторії проєкту: SwitchFix
2. Ініціалізуй git: `git init`
3. Почни з Milestone 0

### Правила виконання

- **Один milestone за раз**. Не починай наступний поки поточний не проходить `swift build`
- **Кожен файл пиши повністю**. Жодних `// TODO`, `// implement later`, або `...`
- **Після кожного milestone**: `swift build 2>&1` — якщо є помилки, фікси їх
- **Після успішного build**: `git add -A && git commit -m "Milestone N: description"`
- **Якщо milestone занадто великий** — розбий на sub-milestones, але все одно верифікуй кожен
- **Тести**: запускай `swift test` після milestone 3, 4, 5 (де є unit тести)
- **Не використовуй зовнішні залежності**: тільки Foundation, AppKit, Carbon (для TIS API), CoreGraphics, ApplicationServices

### Обмеження середовища

- У тебе немає Xcode GUI — тільки command line tools (`swift`, `swiftc`, `swift build`, `swift test`)
- У тебе немає доступу до інтернету — не завантажуй нічого через curl/wget
- Словники генеруй програмно (hardcoded word lists в Swift source, write to file)
- Для тестування GUI — описуй що потрібно перевірити вручну

### Очікуваний результат

Після виконання всіх milestone: робочий .app bundle який можна запустити на macOS Apple Silicon, що автоматично виправляє неправильну розкладку клавіатури для EN/UK/RU.

---

## РОЗШИРЕННЯ НА МАЙБУТНЄ (не імплементувати зараз)

- Підтримка додаткових мов (German, Polish, etc.)
- Machine learning-based detection (замість dictionary lookup)
- Sentence-level context (враховувати попередні слова)
- Custom user dictionary
- Автоматичне оновлення словників
- iOS/iPadOS companion app
- Accessibility API v2 для macOS 15+
