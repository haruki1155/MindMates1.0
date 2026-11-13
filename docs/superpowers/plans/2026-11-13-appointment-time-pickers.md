# Appointment time pickers (items 50–51) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the hand-typed "Best Time to Contact You" with day and time pickers, and shrink the appointment time step from large slot cards to compact chips.

**Architecture:** A small pure library formats and parses the one sentence the app already saves, so nothing downstream changes. The intake form hosts a `FormField<BestContactTime>` so it validates with the existing form. The time step keeps the server's hours and only changes how they are drawn.

**Tech Stack:** Flutter (Dart), Provider, `showTimePicker`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-13-appointment-time-pickers-design.md`

## Global Constraints

- **Branch:** `feat/appointment-time-50-51`, cut from `origin/main`. Never push without the user asking.
- **Clean tree:** after every `flutter` command run `git checkout -- pubspec.lock linux macos windows`. Run `dart format` only on the files you touched, and check the diff for lines you did not intend.
- **Test command:** `flutter test --dart-define=APP_ENV=staging`.
- **Saved string is canonical, not localised:** always `"<Days>, <h:mm AM/PM> – <h:mm AM/PM>"`, for example `Weekdays, 9:00 AM – 12:00 PM`. The separator is an en dash (`–`) with a space either side. On-screen picker fields display the device's own format instead, via `MaterialLocalizations.formatTimeOfDay`.
- **Day labels, exactly:** `Weekdays`, `Weekends`, `Any day`.
- **Defaults:** days `Weekdays`, start 9:00 AM, end 12:00 PM.
- **Untouched:** `AppointmentModel`, Firestore fields, callables, rules, admin screens, the step order, and which hours the server offers.

## Review Focus

1. **End equal to start** (9:00 AM to 9:00 AM) must be rejected, not saved as a zero-length window — Task 2.
2. **A best time typed before this change** ("Weekend mornings 9 AM - 12 PM") must reopen without crashing, falling back to the defaults — Tasks 1 and 2.
3. **A 24-hour device** must show 24-hour fields while the saved sentence stays canonical 12-hour, so PACC always reads the same shape — Tasks 1 and 2.
4. **A 360 px screen at large text** must wrap the hour chips without overflow and keep 44 px tap targets — Task 3.
5. **A reversed overnight range** (11:00 PM to 1:00 AM) must be rejected by the same rule, since the field is a same-day contact window — Task 2.

---

### Task 1: Best contact time: format and parse

**Files:**
- Create: `lib/features/counseling/domain/best_contact_time.dart`
- Test: `test/features/counseling/best_contact_time_test.dart`

**Interfaces:**
- Produces:
  - `enum BestContactTimeDays { weekdays, weekends, anyDay }` with `String get label` → `Weekdays`, `Weekends`, `Any day`.
  - `class BestContactTime { const BestContactTime({required this.days, required this.start, required this.end}); final BestContactTimeDays days; final TimeOfDay start; final TimeOfDay end; static const defaults = BestContactTime(days: BestContactTimeDays.weekdays, start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 12, minute: 0)); bool get isValidRange; }` — `isValidRange` is true only when `end` is strictly later than `start` in minutes from midnight.
  - `String formatBestContactTime(BestContactTime value)` — canonical, per Global Constraints. Hour 0 prints as `12`, hour 13 as `1 PM`, minutes always two digits.
  - `BestContactTime? parseBestContactTime(String raw)` — the exact inverse; returns `null` for anything that does not match, including an empty string.

- [ ] **Step 1: Write the failing tests**

```dart
test('formats the canonical sentence', () {
  expect(formatBestContactTime(BestContactTime.defaults), 'Weekdays, 9:00 AM – 12:00 PM');
  expect(
    formatBestContactTime(const BestContactTime(
      days: BestContactTimeDays.anyDay,
      start: TimeOfDay(hour: 0, minute: 5),
      end: TimeOfDay(hour: 13, minute: 30))),
    'Any day, 12:05 AM – 1:30 PM');
});
test('parses what it formats, for every day choice', () {
  for (final days in BestContactTimeDays.values) {
    final value = BestContactTime(days: days, start: const TimeOfDay(hour: 7, minute: 45), end: const TimeOfDay(hour: 19, minute: 0));
    final parsed = parseBestContactTime(formatBestContactTime(value));
    expect(parsed?.days, days);
    expect(parsed?.start, const TimeOfDay(hour: 7, minute: 45));
    expect(parsed?.end, const TimeOfDay(hour: 19, minute: 0));
  }
});
test('returns null for free text typed before this change', () {
  for (final raw in ['', '   ', 'Weekend mornings 9 AM - 12 PM', 'Weekdays, 9:00 AM to 12:00 PM', 'Someday, 9:00 AM – 12:00 PM']) {
    expect(parseBestContactTime(raw), isNull, reason: raw);
  }
});
test('range validity', () {
  expect(BestContactTime.defaults.isValidRange, isTrue);
  expect(const BestContactTime(days: BestContactTimeDays.weekdays, start: TimeOfDay(hour: 9, minute: 0), end: TimeOfDay(hour: 9, minute: 0)).isValidRange, isFalse);
  expect(const BestContactTime(days: BestContactTimeDays.weekdays, start: TimeOfDay(hour: 23, minute: 0), end: TimeOfDay(hour: 1, minute: 0)).isValidRange, isFalse);
});
```

- [ ] **Step 2: Run the tests and confirm they fail**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/counseling/best_contact_time_test.dart`
  - Expected: compile FAIL, because the file does not exist.
- [ ] **Step 3: Implement `best_contact_time.dart`** per the Interfaces block. The file imports only `package:flutter/material.dart` for `TimeOfDay`; it holds no widgets.
- [ ] **Step 4: Run the tests and confirm they pass.** Same command. Expected: all pass.
- [ ] **Step 5: Commit**

```bash
git add lib/features/counseling/domain/best_contact_time.dart test/features/counseling/best_contact_time_test.dart
git commit -m "feat(appointment): canonical best contact time format and parse (50)"
```

### Task 2: Best Time pickers in the intake form

**Files:**
- Modify: `lib/features/counseling/screens/pacc_counseling_screen.dart`
  - state field and `_bestTimeController` at `:46`, `:93`, `:129`, `:246`, `:358`, `:428`
  - `_IntakeFormView` parameter at `:1265`, `:1290`, and the field at `:1497-1502`
- Test: `test/features/counseling/pacc_best_time_test.dart`

**Interfaces:**
- Consumes: Task 1's `BestContactTime`, `BestContactTimeDays`, `formatBestContactTime`, `parseBestContactTime`.
- Produces: a private `_BestTimeField` widget in the same screen file:
  `const _BestTimeField({required BestContactTime value, required ValueChanged<BestContactTime> onChanged})`. It is a `FormField<BestContactTime>` so the existing `_formKey.currentState!.validate()` (`:369`) covers it. Its `validator` returns `'End time must be after the start time.'` when `!value.isValidRange`, otherwise `null`.
  Keys for tests: `Key('best-time-days-weekdays' | '…-weekends' | '…-anyDay')`, `Key('best-time-start')`, `Key('best-time-end')`.

**Replacing the controller:** delete `_bestTimeController` and hold `BestContactTime _bestTime = BestContactTime.defaults` instead. Reset it to `BestContactTime.defaults` where the controller was cleared (`:93`), drop its `dispose` (`:129`), prefill with `parseBestContactTime(priorAppointment.bestTime ?? '') ?? BestContactTime.defaults` (`:358`), and save `formatBestContactTime(_bestTime)` (`:428`). `_IntakeFormView` takes `bestTime` and `onBestTimeChanged` in place of `bestTimeController`.

**Layout:** under the existing `_FieldLabel('Best Time to Contact You*')`, a segmented row of the three day choices, then a row of two tappable fields labelled **From** and **To**, each showing `MaterialLocalizations.of(context).formatTimeOfDay(…)` with a schedule icon, each opening `showTimePicker` with that value as `initialTime`. A dismissed picker leaves the value unchanged. The error text renders below in the form's usual error style.

- [ ] **Step 1: Write the failing widget tests.** Pump `PaccCounselingScreen` with the providers the existing `test/features/counseling/pacc_start_booking_protection_test.dart` uses, with `startBooking: true` so it opens on the intake step.
  - `'shows the default contact window'`: `find.text('9:00 AM')` and `find.text('12:00 PM')` each find one widget, and `find.byType(TextField)` does not match a best-time box.
  - `'rejects an end at or before the start'`: set the value through the field's `onChanged` to start 9:00 AM / end 9:00 AM, submit the form, and expect `find.text('End time must be after the start time.')` findsOneWidget; repeat with 11:00 PM → 1:00 AM.
  - `'reopening free text falls back to the defaults'`: pump with a prior appointment whose `bestTime` is `'Weekend mornings 9 AM - 12 PM'`; expect no exception and the defaults shown.
  - `'a 24-hour device shows 24-hour fields'`: wrap in `MediaQuery(data: MediaQueryData(alwaysUse24HourFormat: true))`; expect `find.text('09:00')` findsOneWidget and `find.text('9:00 AM')` findsNothing.
  - `'the saved appointment carries the canonical sentence'`: drive the booking to the point where the appointment is built, with days Weekends and 8:00 AM – 10:00 AM, and assert the captured `AppointmentModel.bestTime` is `'Weekends, 8:00 AM – 10:00 AM'` regardless of `alwaysUse24HourFormat`.
- [ ] **Step 2: Run the tests and confirm they fail**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/counseling/pacc_best_time_test.dart`
  - Expected: FAIL — the text field is still there and the keys do not exist.
- [ ] **Step 3: Implement `_BestTimeField` and the state changes** described above.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the new file, then `flutter test --dart-define=APP_ENV=staging test/features/counseling`. Expected: all pass.
- [ ] **Step 5: Commit**

```bash
git add lib/features/counseling/screens/pacc_counseling_screen.dart test/features/counseling/pacc_best_time_test.dart
git commit -m "feat(appointment): pick the best contact window instead of typing it (50)"
```

### Task 3: Compact hour chips

**Files:**
- Modify: `lib/features/counseling/screens/pacc_counseling_screen.dart` — `_TimeCard` (`:1186-1229`) and its `Wrap`/`LayoutBuilder` host (`:1136-1157`)
- Test: `test/features/counseling/pacc_time_chips_test.dart`

**Interfaces:**
- Produces: `_TimeChip` replaces `_TimeCard` with the same three parameters (`time`, `selected`, `onTap`) and key `Key('time-chip-$time')`. Height 40, horizontal padding 16, `StadiumBorder`. Unselected: white fill, 1 px `Color(0xFFE5C24D)` border. Selected: `_PaccColors.sun` fill, 1.5 px `_PaccColors.sunButton` border, and a 16 px `Icons.check` before the label. The host becomes a plain `Wrap(spacing: 10, runSpacing: 10)` with no `LayoutBuilder` and no per-item `SizedBox`.

- [ ] **Step 1: Write the failing widget tests.** Pump the time step with three offered hours, through the same provider setup as Task 2.
  - `'shows one chip per offered hour and no cards'`: three `_TimeChip`-keyed finders match; `find.text('Available')` findsNothing; no widget is 104 px tall.
  - `'choosing an hour enables Continue to Confirm'`: the button is disabled first, then tapping `Key('time-chip-10:00 AM')` enables it and marks that chip selected.
  - `'chips wrap without overflow at 360 px with large text'`: surface 360×900 and `textScaleFactorTestValue = 1.4`; expect `tester.takeException()` isNull and every chip at least 44 px tall.
- [ ] **Step 2: Run the tests and confirm they fail**
  - Run: `flutter test --dart-define=APP_ENV=staging test/features/counseling/pacc_time_chips_test.dart`
  - Expected: FAIL — the keys do not exist and "Available" is still rendered.
- [ ] **Step 3: Implement `_TimeChip`** and simplify the host.
- [ ] **Step 4: Run the tests and confirm they pass.** Run the new file, then `flutter test --dart-define=APP_ENV=staging test/features/counseling`. Expected: all pass.
- [ ] **Step 5: Commit**

```bash
git add lib/features/counseling/screens/pacc_counseling_screen.dart test/features/counseling/pacc_time_chips_test.dart
git commit -m "feat(appointment): compact hour chips in place of slot cards (51)"
```

### Task 4: Verify and install

- [ ] **Step 1: Run the full checks.**
  - `flutter analyze` → "No issues found!".
  - `flutter test --dart-define=APP_ENV=staging` → "All tests passed!".
- [ ] **Step 2: Clean the tree.** `git checkout -- pubspec.lock linux macos windows`, then `git status --short` → empty.
- [ ] **Step 3: Install on the Infinix `13195704C5003842`** with `--flavor staging --dart-define=APP_ENV=staging` and check:
  - the intake form has no typed best-time box, and the pickers open and save;
  - the time step shows compact chips, and "Continue to Confirm" only enables once an hour is chosen;
  - a completed booking's details sheet reads "Best contact time: Weekdays, 9:00 AM – 12:00 PM".
