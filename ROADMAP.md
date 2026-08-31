# Roadmap

Ordered by what would break a production launch first, not by what's most
interesting to build.

Three of these — the Experience Cloud storefront, rich message options, and
human escalation — were named directly. The rest are gaps found while
building and documenting the system.

---

## Tier 0 — blocks production

Nothing else on this list matters until these are done.

### 0.1 Apex test classes

**Status: not started. Coverage is 0%.** Salesforce will not accept a
production deployment below 75%, and more to the point, eight classes with
branching logic and no tests is a system nobody can safely change.

Needed, one test class per action class plus two for the services:

| Test class | Must cover |
|------------|------------|
| `WarrantyDeskTest` | `claimRecordTypeId()` when the record type is *not* available (returns null — this is the live org's actual state), `nameMatches()` first-token and last-token hits, `warrantyActive()` at the exact boundary date, `looksLikeEmail()` rejects |
| `OrderWarrantyServiceTest` | Asset creation count matches order line count, serial format, `QR_Email_Sent__c` flips exactly once (re-activation must not re-send), deep link string composition |
| `CheckSerialRegistrationActionTest` | Unknown serial, known+unregistered, known+already-registered |
| `RegisterWarrantyActionTest` | Sets end date = purchase date + months, refuses a second registration |
| `GetCustomerAssetsActionTest` | Empty email returns empty *and says so distinctly from "no products"* — this is the v4 bug's regression test |
| `CreateWarrantyClaimActionTest` | Case created with the right Asset, `Claim_Stage__c` defaults, null `RecordTypeId` tolerated |
| `GetClaimStatusActionTest` | No claims, one claim, multiple claims |
| `SchedulePickupActionTest` | Writes `Pickup_Slot__c`, rejects a past datetime |
| `OrderWarrantyTriggerTest` | Bulk: 200 orders activated in one transaction stays inside governor limits |

The trigger test is not optional. `OrderWarrantyService.handleActivation()`
does SOQL and DML; a data-loader import of 200 orders is a realistic event.

**Effort: 2–3 days. Do this first.**

### 0.2 Prove the claim path live on v4

Registration passed. Claim intake, status, pickup and escalation have not
had a clean live conversation since the v4 agent rewrite. The v3→v4 change
(filling conversation values at point of use instead of via setters) was
significant enough that the earlier passes don't carry forward.

Run the seven-step smoke test in `scripts/post-deploy-checklist.md` §9
against the live Apple channel and fix what falls over. Verify Case
creation **in the org**, not by reading what the agent said — the v2 bug
was the agent narrating a success that never happened.

### 0.3 Move `APPLE_BUSINESS_ID` to Custom Metadata

Hard-coded in `OrderWarrantyService.cls`. Every sandbox refresh, every new
org, every environment gets the wrong QR destination until someone
remembers to edit Apex. A `WarrantyDesk_Setting__mdt` with
`Apple_Business_Id__c` and `Apple_Intent_Id__c` fixes it permanently and
takes an hour.

---

## Tier 1 — the three named priorities

### 1.1 Rich messages: options instead of plain text

Right now every prompt is prose and every reply is free typing. "Which
product is this about?" followed by the customer typing a model number is
worse in every way than three tappable buttons — slower, more error-prone,
and it's the single biggest source of the parsing ambiguity that caused two
of the three live-test failures.

Apple Messages for Business supports four interactive types, and Salesforce
Enhanced Messaging exposes them:

| Apple type | Where it belongs in this flow |
|------------|-------------------------------|
| **Quick Reply** | Yes/no confirmations; "Register a warranty / File a claim / Check status / Talk to someone" as the opening menu |
| **List Picker** | "Which of your products?" — populated live from `GetCustomerAssetsAction` |
| **Time Picker** | Pickup scheduling. This is the natural fix for §2.3 below |
| **Form** | Multi-field claim intake — defect category + description in one screen |

**How to build it.** Enhanced Messaging channels send structured content
through `ConversationChannelDefinition` / messaging components rather than
raw text. Two viable routes:

1. **Static menus** — configure Quick Reply option sets on the messaging
   channel for the fixed choices (main menu, yes/no). Fastest win, no code.
2. **Dynamic pickers** — the action's Apex returns a structured payload the
   agent renders as a List Picker. This is the one that matters, because
   the product list is per-customer. Requires the action's output shape to
   carry option ids alongside labels, and the agent instruction to emit a
   picker rather than prose.

Start with (1) for the opening menu and the confirmations — it's an
afternoon and it removes the most common misreads. Then (2) for product
selection.

**A caution:** the agent's `available when` gates key off conversation
variables. When a picker sets a variable directly instead of the planner
inferring it from prose, some gates get simpler and some become redundant.
Re-read the gate logic when you wire this up rather than layering pickers
on top of the existing prose flow.

### 1.2 Escalation to a human agent

Partly built. `MessagingChannel.FallbackQueueId` points at **Warranty
Support**, the queue exists with `Apple_Routing` attached, the presence
status deploys, and the `escalation` subagent exists. What's missing is
everything that makes it actually work:

| Gap | What to do |
|-----|------------|
| **The queue has no members** | Add users or a public group. An escalation into an empty queue waits forever, and the customer sees silence |
| **No handoff context** | The rep picks up a conversation with no summary. Build a "conversation summary" step that writes what the agent gathered — serial, defect, claim id — into the MessagingSession before transfer |
| **No agent-side console layout** | There is no MessagingSession Lightning record page. The rep sees a bare session with no Asset, no Case, no warranty status alongside it. Build one |
| **No business-hours awareness** | The agent will happily offer a human at 2am. Wire Business Hours into the escalation gate and offer a callback instead when closed |
| **No escalation triggers beyond asking** | Should also escalate on: repeated failed serial lookups, an out-of-warranty claim, explicit frustration, or three turns without progress |

The last row is the one that changes customer experience most. An agent
that recognises it's failing and hands off beats one that has to be asked.

**Effort: queue members and the record page are a day. Summary handoff and
smart escalation triggers, a week.**

### 1.3 Experience Cloud storefront (React)

The intended front end: a site where customers buy products, receive the QR
email, and land in Messages. Today the order arrives by whatever means, and
the storefront doesn't exist.

**Architectural decision to make first.** Two genuinely different paths:

| | LWR + custom LWCs | React app on LWR |
|---|---|---|
| **How** | Lightning Web Runtime site, components in LWC | React bundled as a static resource, mounted inside one LWC host |
| **Auth** | Native — Experience Cloud handles login, sharing, guest access | Native for the shell; the React app needs the session passed in |
| **Data** | Wire adapters, no API layer to write | Fetch against Apex `@AuraEnabled` or a REST layer you build |
| **Ecosystem** | Salesforce component ecosystem | Full npm ecosystem, React Router, your existing component library |
| **Cost** | Learning LWC | Building and maintaining the bridge |

React was the stated preference. That's a real choice — but be clear that
"React on Experience Cloud" means React inside a single LWC host with a
hand-built data bridge, not a standalone React app with Salesforce as a
backend. If the site is mostly catalogue and checkout, LWR + LWC will ship
faster. If it's a rich app with heavy client state, React earns its bridge.

**Third option worth pricing:** a standalone Next.js/Vite app deployed
anywhere, talking to Salesforce over a Connected App + OAuth. Cleanest
React experience, no Experience Cloud licence per customer, but you own
auth, hosting and the session bridge entirely.

**What the site needs regardless of choice:**

```
Catalogue ──► Product detail ──► Cart ──► Checkout
                                            │
                                            ▼
                                   Order (Draft → Activated)
                                            │
                                            ▼
                              OrderWarrantyTrigger fires
                              (already built — this is the seam)
                                            │
                                            ▼
                                  Assets + QR email
```

The good news: **the trigger is the integration point and it already
works.** The storefront's only obligation is to create an Order with
OrderItems and activate it. Everything downstream is done.

Also needed: a logged-in "My Products" page showing Assets and warranty
status (the same data `GetCustomerAssetsAction` returns — consider a shared
service class so web and agent can't drift), and a claim history view.

**Effort: 4–8 weeks depending on path and catalogue complexity.**

---

## Tier 2 — completes what's half-built

### 2.1 Wire up photo capture

The agent asks for a photo of the defect. Nothing receives it. No
`ContentVersion` id reaches `CreateWarrantyClaimAction`, so the image —
if the customer sends one — lands in the messaging transcript and never
attaches to the Case.

Apple Messages supports image attachments natively; they arrive as
`ContentVersion` records linked to the MessagingSession. The work is:
find them, and `ContentDocumentLink` them to the Case at creation.
Add an optional `photoContentVersionId` input to the action.

Claims with photos resolve faster. This is a small change with real value.

### 2.2 Rep-side claim workflow

A claim gets filed and then... nothing. No notification, no approval, no
SLA, no way for a rep to move it through stages except editing a picklist
by hand.

Build:

- **Notification on claim creation** — Flow or Platform Event to the
  Warranty Support queue
- **Approval process** on `Claim_Stage__c` — Under Review → Approved /
  Rejected, with a rejection reason
- **Customer notification on stage change** — an outbound message back into
  the same Apple conversation is the right call here, not email. The thread
  is where the customer already is
- **Entitlements / Milestones** for SLA tracking

### 2.3 Real pickup availability

`SchedulePickupAction` writes whatever datetime it's given. The windows the
agent offers come from its instructions — they are, bluntly, made up. A
customer can be promised a slot that nobody can service.

Minimum viable fix: a `Pickup_Slot__c` custom object with capacity per day
per region, queried before the agent offers anything. Better: Salesforce
Field Service, if logistics justify it.

Pair this with the Apple **Time Picker** (§1.1) — the customer sees only
real, available slots and taps one. The two changes are much stronger
together than separately.

### 2.4 Purchase date and serial integrity

Two data problems:

- **`Asset.PurchaseDate` is set from the order date.** For a product that
  ships weeks after ordering, the warranty starts too early. Capture actual
  delivery, or let registration set it from what the customer states.
- **Serial numbers have no uniqueness constraint.** `SN-{OrderNumber}-{n}`
  is unique by construction *today*, but nothing enforces it. Mark
  `SerialNumber` unique, or a duplicate silently registers a warranty
  against the wrong asset.

### 2.5 Generate the QR in Apex

Currently the QR image comes from an external image URL. That means: a
third-party dependency in an email your customers receive, the deep link
transiting someone else's service, and a broken image if that service
changes. Generate it in Apex and attach it — a QR encoder is a few hundred
lines, or use a licence-free library as a static resource.

---

## Tier 3 — scale and polish

### 3.1 Multi-channel

Everything below the messaging channel is channel-agnostic. Adding WhatsApp
or web chat is: register the channel, point `SessionHandlerId` at the same
agent, done. The Apex and the agent don't change. (WhatsApp was explicitly
out of scope for v1 — this notes that the door is open, not that it should
be opened.)

### 3.2 Localisation

Every string is English and most are inline in agent instructions. If the
product sells outside one market this becomes a rewrite, not a
translation. Custom Labels for Apex strings; the agent bundle needs a
per-language strategy.

### 3.3 Analytics

Nothing measures whether this works. Worth tracking: containment rate
(conversations resolved without a human), registration completion rate,
where customers drop out of claim intake, average turns to resolution,
escalation reasons. A CRM Analytics dashboard or a handful of reports on
MessagingSession + Case.

### 3.4 Bulk registration

A distributor buying forty pumps should not have forty conversations.
Accept an order number and register everything on it at once.

### 3.5 Warranty expiry outreach

Nothing tells a customer their warranty is ending. A scheduled job 30 days
out, messaged into the existing Apple thread, is both a service and an
extended-warranty sales channel.

### 3.6 Proactive claim updates

The customer currently has to ask for status. Push stage changes into the
thread instead. Combined with §2.2's approval process this closes the loop
without anyone opening a portal.

---

## Suggested sequence

```
Now        ── 0.1 tests · 0.2 prove claim path live · 0.3 custom metadata
Next       ── 1.1 quick replies (static) · 1.2 queue members + record page
Then       ── 2.1 photos · 2.2 rep workflow · 1.1 dynamic list pickers
In parallel── 1.3 storefront architecture decision, then build
Later      ── 2.3 pickup availability + time picker · 2.4 data integrity
Eventually ── tier 3
```

Tier 0 is roughly a week. Tier 1 without the storefront is three to four.
The storefront is its own project.
