# MindMate: Student accounts — how it works now

Students no longer create their own MindMate accounts. The PACC office imports the official
student list, and each student claims their own record using a one-time activation code.

This guide covers what each person does.

---

## Before students can use it

Two things must be done once, by whoever manages the system:

1. Deploy the updated app and backend (the new screens will not work against the old backend).
2. Run the one-time "info requirement" update so students who already had accounts are asked
   to complete their Student Information form.

Until both are done, the activation screen will not work. Your developer has the exact steps.

---

## For the PACC office (admin)

### 1. Import the student list

Open **Student Roster** in the admin portal.

1. Tap **Download template**. It gives you a spreadsheet with these columns:
   Student No., Surname, First Name, Middle Name, Date of Birth (MM/DD/YYYY), College, Course, Year Level.
2. Fill it from the registrar's list. Keep the column headings exactly as they are.
   - Format the Student No. column as **Text** so numbers like `02100123` keep their leading zero.
   - College and Course must match the names already set up in Academic Structure.
3. Tap **Choose file**, pick your spreadsheet, then tap **Preview**.
4. The preview shows every row and what will happen to it:
   - **New** — a student who will be added.
   - **Update** — already on the roster; shows exactly what changes.
   - **Links account** — matches a student who already signed up the old way. Their existing
     account is kept and linked.
   - **Error** — something is wrong with that row. Dates are spelled out ("Feb 3, 2005") so you
     can spot a swapped day and month.
   - A **warning** on a "Links account" row means the existing account's name or birthday does
     not match your file. Check that row against the registrar's list before importing — it can
     mean someone typed the wrong Student No. when they signed up.
5. If any row shows an error, fix the spreadsheet and preview again. Nothing is saved until the
   whole file is clean.
6. Tap **Import**.

### 2. Hand out the activation codes

After importing, the page shows **Download activation slips**. This is the only time the codes
are shown.

- Download the slips before leaving the page. The app warns you if you try to leave, sign out,
  or close the tab while codes are not yet saved.
- Each slip has one student's name, course, their code (like `K4M2P-R8TQW`), and an expiry date.
  Codes last 60 days.
- Give each student their own slip. Do not post a list where others can see it — the code is
  what proves the account is theirs.

Lost a slip? Find the student in the roster list and choose **Issue new activation code**. The
old code stops working immediately.

### 3. Day-to-day roster management

Search the roster by Student No. or surname, and filter by college, course, year level, or status:

- **Not activated** — has not claimed their account yet.
- **Activated** — using the app.
- **Info incomplete** — has not finished the Student Information form.
- **Legacy, not in roster** — had an account before the import and is not in your file. Check
  whether they belong; add them to the next import if so.

Each row offers:

- **Edit record** — correct the official details (name, college, course, year level, birthday).
  Use this when a student needs both their college and course changed, which the request system
  cannot do on its own.
- **Request corrections** — approve or reject what students have asked you to fix.
- **Issue new activation code** — for a lost or expired slip.
- **Revoke activation** — if the wrong person claimed a record. This disables that login
  immediately, frees the Student No., and gives you a fresh code for the real student. Nothing
  is deleted; you must give a reason, which is recorded.
- **Deactivate** — for students who have left. Reversible, and no data is removed.

---

## For students

### Activating your account

1. Open MindMate and tap **Activate student account**.
2. Enter your **Student No.**, the **activation code** from your PACC slip, and your **date of birth**.
3. Enter your email address and choose a password.
4. Open the verification link sent to your email.

If the details do not match, the app says so without telling you which part was wrong — that is
deliberate, so nobody can guess their way into someone else's account. After five wrong tries,
that Student No. is locked for 30 minutes.

Mistyped your email? Tap **Cancel registration** on the verification screen. Your slip works again.

From then on you sign in with your **Student No. and password**, as before.

### Your Student Information

The first time you sign in, you are asked to complete the Student Information form — the same
details as the paper form: sex, civil status, nationality, place of birth, your addresses,
parents, guardian, and contact numbers.

- You must first agree to the Data Privacy notice. Nothing is saved until you do.
- Your **guardian** details and **cellphone number** are required. They are how the counselors
  reach someone if you ever need urgent help.
- Your name, Student No., college, course, year level and birthday are shown but locked, because
  they come from the registrar's records.

You can change your own details anytime from **Profile → Student Information**.

### Fixing a locked detail

If something official is wrong, tap **Request correction** next to it, enter the correct value
and a short reason. The PACC office reviews it, and you can see the status of your request on
the same screen. Your Student No. itself cannot be changed this way — ask the PACC office.

### Who can see your information

Only you, the counselors, and the system administrator. Every time a counselor opens your
Student Information, that is recorded with their name and the time. Other staff in the portal
cannot see it at all.

---

## For counselors

Where you see a student — in your cases, follow-ups, appointments, or their profile — there is a
**View Student Information** button. It shows their contact details, addresses, family and
guardian information.

Opening it is recorded in the access log, with your name, the student, and the time. The sheet
says so at the bottom. Only open a student's record when you need it for their care.

Administrators can review these access records in the activity log by choosing the
**Student information viewed** filter.

---

## For teaching and non-teaching staff

Nothing changes for you. Keep using **Employee sign up** with your `@ucu.edu.ph` address and
your Employee ID.

Note: the app currently registers every employee as Teaching. If you are non-teaching staff, ask
an administrator to correct your role after you sign up.
