# Items 50–51: Appointment time pickers (short design)

Status: for approval. Branch `feat/appointment-time-50-51`, cut from `origin/main`. It shares no files with the branches for items 38 and 40–41, so it needs no stacking and can be reviewed on its own.

## 1. Intent

Two panel items on the PACC booking flow, both about replacing clumsy time entry:

- **50** Appointment > Best Time: use a time picker instead of manual input.
- **51** Appointment > Next: minimise the time picker by removing slot-based time selection.

## 2. How it works today

The whole flow lives in `lib/features/counseling/screens/pacc_counseling_screen.dart` (2374 lines). Its steps run `intake → calendar → time → review → confirmation` (`:2187`), starting at `intake` (`:49`).

- **Intake (item 50).** "Best Time to Contact You*" is a required free-text field (`:1497-1502`) with the hint *"e.g. Weekend mornings 9 AM - 12 PM"*. It is **when PACC may contact the student**, not the appointment time. It is stored as the plain string `AppointmentModel.bestTime` (`lib/models/appointment_model.dart:118`), capped at 120 characters by the callable (`functions/src/index.ts:1985`), and shown back as "Best contact time: …" in `appointment_details_sheet.dart:96-99`. Editing an earlier request copies the raw string into the box (`:358`).
- **Time (item 51).** After a date is chosen, `_selectDate` (`:285`) asks `AppointmentProvider.getAvailableSlots`, which calls `getAvailableAppointmentSlots` and returns PACC's genuinely open hours. Each one renders as a large `_TimeCard` in a `Wrap`, one per row below 430 px (`:1136-1157`), so a normal day of availability fills the screen.

## 3. The constraint that shapes item 51

Slots are not decoration. `validateAppointmentTimestamp` (`functions/src/appointment_scheduling.ts:40-60`) rejects any time that is not exactly on the hour, with *"Choose a supported appointment time slot."* (`slotIntervalMinutes: 60`, `:6`), and the slot list also reflects opening hours and what is already booked.

So a free time picker would let someone pick 10:23 or a closed hour and fail only at submission. **"Minimise the time picker" is therefore read as: keep the real hours, show them compactly.** That removes the clunky grid, which is the complaint, without breaking booking. Confirmed with the user.

## 4. Goals

1. Nobody types a time by hand anywhere in booking.
2. "Best time" still carries a usable window for PACC: a range of hours plus which days.
3. The time step fits in a few lines instead of filling the screen, while still offering only hours PACC actually has.
4. No change to the database, the Cloud Functions, or what PACC sees.

## 5. Non-goals and anti-goals

**Non-goals**
- No change to `AppointmentModel`, Firestore fields, callables, rules or admin screens.
- No change to the step order, the calendar, review, confirmation, or the reschedule entry points.
- No change to which hours are offered; that stays the server's answer.

**Anti-goals**
- Letting someone choose a time the server will reject.
- Hiding availability behind a tap, so a student cannot see at a glance whether a day is busy.
- Losing the day part of "best time", which is what makes the field useful to a counselor.

## 6. Approaches

- **A (chosen): pickers in the app, one sentence saved.** The pickers compose the existing `bestTime` string; the time step keeps server hours but renders them as compact chips. No model, server or admin change.
  - Trade-off: `bestTime` stays free text in the database, so older requests keep whatever was typed and it cannot be reported on as structured data later.
- **B: structured fields.** Add start, end and days through the model, the write path and server validation. Rejected: a Functions change and deploy, plus admin and rules checks, for an identical screen.
- **C: keep the text box, add a "pick a time" helper that types into it.** Rejected: manual input remains, which is what item 50 asks to remove.

## 7. Design

### 7.1 Item 50 — Best Time becomes pickers

The field is replaced by a labelled group, still required, still under the same "Best Time to Contact You*" label:

- **Days:** a three-way segmented choice — **Weekdays** (default), **Weekends**, **Any day**.
- **From** and **To**: two tappable fields that open Flutter's standard `showTimePicker`. Defaults 9:00 AM and 12:00 PM, which match today's hint.
- The pair reads as `9:00 AM – 12:00 PM`, in the device's 12/24-hour format via `MaterialLocalizations.formatTimeOfDay`.

**What gets saved** is the same single string the app already stores, composed as `"<Days>, <From> – <To>"`, for example `"Weekdays, 9:00 AM – 12:00 PM"`. Nothing downstream changes.

**Validation** replaces the old "Required": the group is valid when **To** is later than **From**. If not, it shows "End time must be after the start time." The days choice always has a value, so it cannot be empty.

**Reopening an earlier request** parses the stored string with a small pure helper. When it matches the composed shape, the pickers show those values; when it does not — anything typed before this change — the pickers fall back to the defaults and the original text is left untouched unless the user edits it.

Helper, in a new `lib/features/counseling/domain/best_contact_time.dart`:

```
class BestContactTime { BestContactTimeDays days; TimeOfDay start; TimeOfDay end; }
enum BestContactTimeDays { weekdays, weekends, anyDay }   // "Weekdays" | "Weekends" | "Any day"
String formatBestContactTime(BestContactTime value, MaterialLocalizations l10n)
BestContactTime? parseBestContactTime(String raw)          // null when it does not match
```

Both functions are pure and unit-tested; the widget only renders them.

### 7.2 Item 51 — compact time chips

`_TimeCard` is replaced by a compact chip in the same `Wrap`:

- Height 40, horizontal padding 16, fully rounded, so three to four fit per row at 390 px.
- Unselected: white fill, 1 px `_PaccColors` border, dark label. Selected: `_PaccColors.sun` fill, dark label, a 1.5 px border and a small check.
- The `Wrap` keeps `spacing: 10, runSpacing: 10` and drops the `LayoutBuilder` width maths, since chips size themselves.
- Everything else on the step is unchanged: the heading, the chosen date, the "no times available" message, the reminder card and "Continue to Confirm", which stays disabled until an hour is chosen.

*My call, agreed with the user:* chips rather than a dropdown, because a dropdown hides how much is free that day behind a tap.

## 8. Constraints

- CI must stay green: `flutter analyze`, `flutter test --dart-define=APP_ENV=staging`, the staging APK build, Functions tests.
- Never commit regenerated `pubspec.lock`, `linux`, `macos` or `windows` files; format only the touched files.
- The chips and the picker fields must keep a 44 px minimum tap target and survive a 360 px screen at large text.

## 9. Calls I made (for the user to check)

1. "Best time" is still saved as one sentence, so no database or server change is needed and PACC's view is untouched.
2. The days choice defaults to **Weekdays**, and the hours to **9:00 AM – 12:00 PM**, matching the hint being replaced.
3. Old free-text answers that do not match the new shape are left alone, and the pickers simply start from the defaults.
4. The time step keeps offering only PACC's real open hours; only their appearance shrinks.

## 10. Files

- `lib/features/counseling/screens/pacc_counseling_screen.dart` — the Best Time group in `_IntakeFormView`, its validation and prefill; `_TimeCard` becomes a chip.
- New `lib/features/counseling/domain/best_contact_time.dart` — format and parse.
- Tests: unit tests for format and parse round-tripping, including a string that does not match; widget tests for the picker group's validation, for the composed string reaching the saved appointment, and for the compact chips selecting an hour and enabling "Continue to Confirm" at 360 px.
