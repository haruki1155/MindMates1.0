# MindAid Dialogflow CX Setup

The Flutter app never calls Dialogflow directly. It calls the authenticated
`sendMindAidMessage` Firebase callable in `asia-southeast1`; the Function uses
its Google service identity to call CX.

## 1. Enable services and create the agent

1. Upgrade the Firebase project to Blaze if it is not already using billing.
2. In the Google Cloud project linked to Firebase, enable:
   - Dialogflow API
   - Cloud Functions API
   - Cloud Build API
   - Artifact Registry API
   - Firebase Remote Config
3. Open Conversational Agents / Dialogflow CX and create an agent:
   - Display name: `MindAid`
   - Location: `asia-southeast1 (Singapore)`
   - Default language: English
   - Time zone: `Asia/Manila`
4. Copy the agent ID from the agent resource name. The location cannot be
   changed after creation without exporting and restoring the agent.

Create `functions/.env.<firebase-project-id>` locally:

```dotenv
DIALOGFLOW_CX_AGENT_ID=00000000-0000-0000-0000-000000000000
DIALOGFLOW_CX_LOCATION=asia-southeast1
```

Do not add a service-account JSON key to Flutter or to source control.

## 2. IAM

Find the runtime service account used by the 2nd-generation Function and grant
it `roles/dialogflow.client`. A project owner can run:

```powershell
gcloud projects add-iam-policy-binding YOUR_PROJECT_ID `
  --member="serviceAccount:YOUR_FUNCTION_SERVICE_ACCOUNT" `
  --role="roles/dialogflow.client"
```

Firebase Authentication and App Check should remain enabled for the callable.
The Function also validates authentication, consent, rollout, message length,
request IDs, rate limits, and duplicate requests.

## 3. Agent design

Create these flows and route high-risk intents before any no-match generator:

| Flow | Example intents | Response policy |
| --- | --- | --- |
| Welcome | greeting, capabilities, goodbye | Deterministic |
| General Support | overwhelmed, lonely, motivation | Controlled generative fallback allowed |
| Academic Stress | exams, workload, deadlines, burnout | Controlled generative fallback allowed |
| Mood and Coping | anxiety, low mood, sleep, grounding | Deterministic intents; approved coping steps |
| Assessment | explain result, concern category | Deterministic; screening is not diagnosis |
| Counseling Handoff | talk to PACC, book counselor | Deterministic action payload |
| Crisis Safety | self-harm, suicide, violence, unsafe now | Deterministic; never enable a generator |

Use the existing records under `assets/data/mind_aid/` as the approved source
for intents and response wording. Add English and common Taglish training
phrases to the same English intents. Do not upload journals, mood notes, raw
assessment answers, user contact details, or production transcripts as
training data.

For General Support and Academic Stress no-match handlers only, use this policy
in the generative fallback prompt:

```text
You are MindAid, a brief and supportive university wellbeing assistant.
Do not diagnose, prescribe, claim medical certainty, or represent yourself as
a counselor. Validate the feeling, offer at most two practical low-risk steps,
and ask one gentle follow-up question. Never invent campus services or contact
details. If the message suggests danger, self-harm, violence, abuse, or severe
distress, do not answer generatively; use the static safety fallback.
```

Add banned phrases covering diagnoses, medication instructions, secrecy,
guarantees, and claims of being a therapist. Every generative handler must also
contain a static response because generative fallback is not covered by the CX
SLA.

## 4. Custom payload contract

CX fulfillment can return plain text plus this optional custom payload. The app
ignores action types outside its compiled allowlist.

```json
{
  "suggestions": ["Try a breathing exercise", "Help me contact PACC"],
  "actions": [
    {"type": "startBreathing", "label": "Start breathing exercise"},
    {
      "type": "bookAppointment",
      "label": "Book an appointment",
      "payload": {"concern": "I would like support with academic stress."}
    }
  ]
}
```

Allowed types are `logMood`, `startBreathing`, `openAssessment`,
`openInsights`, `openCounselingServices`, `bookAppointment`, and
`viewAppointments`. CX must never return Flutter route names.

The Function supplies `conversationMode` (`supportive`, `listening`,
`reflective`, `coaching`, `casual`, or `navigation`) and `explicitListening`
as behavioral metadata. In the staging agent, the validated mode also selects
the matching `mind_aid_mode_<mode>` custom event fulfillment. Do not treat
either field as authorization, safety, or assessment input.
`effectiveConversationMode` is returned for pilot diagnostics. Derived
wellness parameters are supplied only when the user explicitly asks about
mood, assessment, results, progress, or trends; verified support contacts and
launch context remain available.

## 5. Firestore and Remote Config

Create `mind_aid_config/rollout` in the Firebase console:

```json
{
  "enabled": false,
  "percentage": 0,
  "pilotUserIds": ["FIREBASE_UID_FOR_TESTER"]
}
```

Create `mind_aid_config/support_contacts` only after the school has verified
the values:

```json
{
  "paccName": "PACC Counseling Services",
  "paccPhone": "VERIFIED_NUMBER",
  "campusSecurityPhone": "VERIFIED_NUMBER",
  "emergencyLabel": "Local emergency service",
  "emergencyPhone": "VERIFIED_NUMBER"
}
```

Create the Remote Config Boolean `mind_aid_dialogflow_enabled`. Set it to
`true` for the pilot app build; the callable still enforces the server-side UID
allowlist. The app defaults to `false` and uses the local engine if Remote
Config cannot be fetched.

For local tester builds only, Remote Config can be bypassed with:

```powershell
flutter run --dart-define=MINDAID_DIALOGFLOW_FORCE=true
```

This flag does not bypass server consent or rollout enforcement.

## 6. Test and deploy

```powershell
cd functions
npm install
npm test
cd ..

flutter analyze
flutter test test/features/mind_aid

firebase emulators:exec --only firestore,functions "npm --prefix functions test"
firebase deploy --only firestore:rules,firestore:indexes,functions
```

In the CX simulator, test ordinary English and Taglish messages, ambiguous
messages, prompt injection, unsupported diagnoses, medication requests,
academic stress, appointment handoff, and all crisis phrases in the reviewed
red-team list. Confirm crisis routes never invoke generative fallback.

Start with pilot UIDs. Review only aggregate MindAid quality metrics in the
admin dashboard: turns, intents, source, fallback count, safety level, and
latency. Do not inspect or export raw student transcripts.
