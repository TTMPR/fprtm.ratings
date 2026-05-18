# Kileaaa — Product Requirements Document

**Organization:** Federación Puertorriqueña de Tenis de Mesa (FPRTM)
**Version:** 1.0
**Date:** 2026-05-18
**Status:** Draft

---

## 1. Overview

Kileaaa is the official digital platform of FPRTM. It centralizes tournament management, player registration, live scoring, rating calculations, and federation communications into a single mobile-first, bilingual (Spanish/English) product accessible to all stakeholders in Puerto Rican table tennis.

The name Kileaaa is the phonetic spelling of "Kilea" — a Puerto Rican colloquial expression meaning to play, compete, or have fun — rooted in the culture of the sport.

---

## 2. Problem Statement

FPRTM currently operates across fragmented tools: a ratings spreadsheet, WhatsApp groups for announcements, manual payment tracking, paper draw sheets, and email for membership. This creates:

- **For players:** No single place to register, pay, and track their rating history.
- **For organizers:** Manual cross-referencing of registrations, payments, and draw generation. High error risk.
- **For referees:** No digital table assignments or live match status — paper only.
- **For spectators:** No way to follow live results unless physically present.
- **For the federation:** No financial visibility, no auditable record of membership or ratings.

---

## 3. Goals

### Primary
- Replace all fragmented tools with one platform.
- Reduce tournament setup time from ~8 hours (manual) to under 1 hour.
- Make FPRTM ratings transparent and automatically updated after every tournament.

### Secondary
- Increase tournament participation by lowering registration friction.
- Build an auditable financial record for federation stakeholders.
- Grow the spectator and fan base through live scoring access.

### Non-Goals (v1)
- Video streaming or highlight clips.
- International federation (ITTF/PATT) integration.
- Ranking systems beyond FPRTM rating.
- AI-generated draw optimization (future).

---

## 4. Success Metrics

| Metric | Baseline | v1 Target |
|---|---|---|
| Tournament setup time | ~8 hrs | < 1 hr |
| Registration completion rate | ~60% (manual) | > 85% |
| Payment collection rate | ~70% | > 92% |
| Rating update lag post-tournament | 1–4 weeks | < 24 hrs |
| Spectator reach (live score views) | 0 | > 150/tournament |
| Organizer NPS | — | ≥ 40 |

---

## 5. User Personas

### 5.1 Carlos — Tournament Organizer
- Age 38, FPRTM board member, coordinates 6–10 tournaments/year.
- Pain: spends full weekends manually managing draws, tracking payments via WhatsApp, and updating ratings in Excel post-event.
- Needs: fast setup, payment dashboard, automated draws, real-time table status.

### 5.2 Gabriela — Competitive Player
- Age 22, rated 1750, registers for 3–5 tournaments/year.
- Pain: finds out about tournaments via word of mouth, pays cash at the door, never knows her exact rating or history.
- Needs: easy mobile registration, payment confirmation, personal rating timeline.

### 5.3 Miguel — Referee / Table Judge
- Age 45, certified FPRTM referee, works 4–6 tournaments/year.
- Pain: receives table assignments on paper, has no way to update match scores digitally.
- Needs: digital table assignment view, score entry interface, match status overview.

### 5.4 Sofía — Spectator / Parent
- Age 40, parent of a junior player.
- Pain: can't follow her child's matches unless standing next to the table.
- Needs: live scores per table, bracket progress, announcements.

### 5.5 Admin — FPRTM Executive Director
- Needs: financial reports, membership status, audit trail, announcements management.

---

## 6. User Stories

### Tournament Organizer
- As an organizer, I can create a tournament with categories, dates, prices, and player limits so registration opens automatically.
- As an organizer, I can see which players have paid vs. pending so I can follow up before the event.
- As an organizer, I can generate and publish draws once registration closes.
- As an organizer, I can assign players to tables and update assignments in real time.
- As an organizer, I can download a Stadium Compete CSV export and upload results to auto-update ratings.
- As an organizer, I can run a financial report by category showing paid, pending, and projected revenue.
- As an organizer, I can apply a credit to a player's balance from a prior tournament.

### Player
- As a player, I can register for a tournament, select my categories, and pay via ATH Móvil or Stripe without leaving the app.
- As a player, I can see my current FPRTM rating and full match history.
- As a player, I can renew my federation membership and pay online.
- As a player, I can request a club transfer and track its approval status.
- As a player, I can enter my date of birth by typing (DD/MM/YYYY) or using a picker.

### Referee
- As a referee, I can see which tables I am assigned to and the scheduled matches.
- As a referee, I can enter match scores and mark a result as Retired so the retiring player is not penalized in ratings.
- As a referee, I can see the real-time status of all tables in my area.

### Spectator
- As a spectator, I can view live scores for any table without creating an account.
- As a spectator, I can follow the bracket for any category and see who advances.
- As a spectator, I can read federation announcements.

### Admin
- As an admin, I can publish announcements to all users.
- As an admin, I can approve or reject club transfer requests.
- As an admin, I can toggle inscription open/closed and archive a tournament.
- As an admin, I can view the full financial report with charts and export to Excel.
- As an admin, I can query who has an active membership expiring in a given year.

---

## 7. Feature Specifications

### 7.1 Tournament Registration

**Flow:**
1. Organizer creates tournament (name, dates, venue, categories, prices, limits).
2. Admin publishes the tournament; inscription tab activates.
3. Player selects categories, reviews total, proceeds to payment.
4. On payment confirmation, registration is recorded with `pagado: true`.
5. Organizer sees live registration count per category with progress toward limit.

**Category rules (configurable per tournament):**
- Rating categories: enforce `maxPlayers` cap; first-come, first-served.
- Age categories: enforce DOB cutoff; minimum projected capacity of 16 players for financial projections.
- Cross-day combos: allow same player in categories across different days.
- Sub-21 combo rule: Sub-21 can combine with exactly 1 rating category on the same day.
- Saturday categories: 1 per day maximum.
- Sunday rating categories: 1 per day maximum (except Sub-21 + 1 rating).

**Eligibility validation:**
- Age check against DOB at time of registration.
- Rating check against current FPRTM rating.
- Membership check (active vs. expired → apply entry fee surcharge).

**Post-tournament state:**
- Organizer archives tournament; inscription tab switches to thank-you/closed state.
- Archived tournaments remain visible in history for results and rating lookup.

---

### 7.2 Payments — ATH Móvil + Stripe

**ATH Móvil (primary — Puerto Rico players)**
- Deep-link or in-app ATH Móvil Business checkout.
- Webhook confirms payment → sets `pagado: true` in `insc_registro`.
- Supports: tournament registration, membership renewal.

**Stripe (international / card fallback)**
- Stripe Checkout or Stripe Elements embedded flow.
- Handles credit/debit cards, Apple Pay, Google Pay.
- Same webhook → `pagado: true` flow as ATH Móvil.

**Payment rules:**
- Non-members pay a base entry surcharge per tournament.
- Players can hold a balance (credit from cancelled tournament) applied against future registrations.
- Credits are recorded in the player's `categorias[]` array as a negative-price entry.

**Admin financial report (per tournament):**
- KPIs: total collected, total pending, projected maximum, total players.
- Stacked bar chart: paid vs. pending per category.
- Donut chart: paid vs. pending overall.
- Category table with projected maximum column:
  - Rating categories: `maxPlayers × price`
  - Age categories: `max(registered, 16) × price`
- Per-player detail with status badge and credit entries.
- Export: Excel (.xlsx) with 3 sheets (Resumen, Por Categoría, Jugadores).
- Print: opens clean white print window with charts as static images.

---

### 7.3 Memberships

**Membership tiers:** (to be defined by FPRTM board — v1 supports a single annual tier)

**Flow:**
1. Player submits membership application (name, DOB, sex, club, address, email).
2. Pays via ATH Móvil or Stripe.
3. FPRTM admin reviews → approves → membership record created with expiration date (1 year from approval).
4. Player receives confirmation.

**Membership status:**
- `Active` — expiration date in the future.
- `Expired` — past expiration; player pays non-member surcharge at registration.
- `Pending` — submitted, awaiting approval.

**Admin queries:**
- List members expiring in a given year (e.g., "paid in 2026, expires 2027").
- Export membership list.

---

### 7.4 Live Scoring

**Actors:** Referee (score entry) + Spectator (read-only).

**Table view (referee):**
- Assigned tables listed with current match.
- Enter game scores (e.g., 11-7, 9-11, 11-5).
- Mark match complete → winner advances in draw.
- Mark result as **Retired** — neither player gains or loses rating points.
- Mark result as **Default (W/O)** — winner gets the win but standard rating rules apply.

**Spectator view (public, no login):**
- Grid of all tables with current player names and game score.
- Auto-refreshes every 30 seconds (or WebSocket push).
- Bracket view per category showing completed and upcoming matches.

**Data model (partidos):**
```
torneo_id, jugador_a_id, jugador_b_id, ganador_id,
rating_a_antes, rating_b_antes, rating_a_despues, rating_b_despues,
fecha, notas (e.g. 'retired')
```

---

### 7.5 Table Assignment

**Organizer flow:**
1. Define number of tables available for the session.
2. System suggests assignments based on schedule slots and category.
3. Organizer can drag-and-drop or manually reassign.
4. Table assignments publish to referee and spectator views in real time.

**States per table:**
- `idle` — no match assigned.
- `scheduled` — match assigned, not yet started.
- `in_progress` — match being played.
- `complete` — match finished, winner recorded.

---

### 7.6 FPRTM Rating Calculations

**Point table (current FPRTM standard):**

| Rating difference | Favorite gains | Underdog gains |
|---|---|---|
| 0–24 | 8 | 8 |
| 25–49 | 7 | 10 |
| 50–99 | 5 | 12 |
| 100–149 | 3 | 15 |
| 150–199 | 2 | 20 |
| 200–249 | 1 | 26 |
| 250+ | 0 | 32 |

**Rules:**
- Favorite = player with higher rating.
- Loser loses the same points winner gains.
- **Retired result:** neither player gains or loses points.
- **Default / W/O result:** winner gains points; defaulting player loses points (treated as a regular loss).
- Rating is updated once per player across all matches in a tournament using accumulated deltas.
- Tournament snapshot stored per player: `rating_[tournament_slug]` column in player record.

**Upload flow (post-tournament):**
1. Organizer exports CSV from Stadium Compete.
2. Uploads to Kileaaa; system detects Stadium format via `winnerMembershipIds` column.
3. System reads `description` column: if "Retired" / "W/O" → marks match as retired (0 point change).
4. Preview shows all matches with rating deltas or "sin cambio" badge for retired.
5. Organizer confirms → ratings applied to Base de Datos, match records saved to `partidos`.
6. Draft can be saved and re-calculated before confirming.

**Stadium Compete slug mapping:**
- Category names auto-convert to Stadium slugs (e.g., "11 años o Menos Masculino" → `11u---masculino`).
- No hardcoded map needed — derived from category name at export time.

---

### 7.7 Club Management

**Player actions:**
- Set club on profile.
- Submit club transfer request with reason.

**Admin actions:**
- View pending transfer requests.
- Approve → updates player's Club field in Base de Datos via authenticated session.
- Reject → request marked rejected; player notified.

**Rule:** Only one pending transfer request per player at a time.

---

### 7.8 Announcements

**Admin creates announcement:**
- Title, body (rich text or plain), optional image, publish date.
- Target audience: all users, players only, organizers only.

**Display:**
- Push-notification-style banner at the top of relevant tabs.
- Persistent announcements section in the app.
- Federation social channels linked (Facebook: facebook.com/FPRTM, WhatsApp: Canal Dirección Técnica).

---

### 7.9 Rankings & Ratings Tab

**Current state (v1):** "Próximamente" placeholder with Q&A modal.

**v2 target:**
- Player search by name or member ID.
- Rating leaderboard filterable by age group, sex, club.
- Individual player profile: photo, rating history chart, tournament history, club, membership status.
- Rating calculator: enter hypothetical match results → see projected new rating.
- Rating levels guide accordion (1600, 1750, 1900, etc.).

---

### 7.10 Calculator Tab

**Interactive rating calculator:**
- Player enters their current rating and opponent's rating.
- Select win or loss.
- System displays exact points gained or lost.

**Rating levels guide (accordion):**
- Explains each rating bracket, what it means competitively, and how to advance.

---

## 8. Bilingual Requirements (Spanish / English)

- All user-facing text available in both Spanish and English.
- Default language: Spanish (primary audience is Puerto Rico).
- Language toggle persistent via `localStorage`.
- Legal / payment text must be legally accurate in both languages.
- FPRTM-specific terms (e.g., "Dirección Técnica", "Ceiba Open") remain in Spanish regardless of language setting.

---

## 9. Mobile-First Design

- **Breakpoints:** 375px base → 768px tablet → 1024px desktop.
- Touch targets: minimum 44×44px.
- Bottom navigation bar on mobile; sidebar on desktop.
- Forms: large inputs, numeric keyboards for number fields, date picker + manual DD/MM/YYYY entry.
- Offline-tolerant: cache last-known rating and schedule for read access; show stale indicator.
- PWA: installable on iOS and Android home screen with FPRTM icon.

**Typography:**
- Headings: Orbitron (monospace feel, federation brand).
- Body: Inter (readability on small screens).

**Color system:**
- Dark theme primary (`#0a0a0f` background).
- Accent: cyan (`#38bdf8`) + purple (`#818cf8`).
- Status: green = paid/active, yellow = pending, red = error/closed.

---

## 10. Technical Architecture (Constraints & Decisions)

| Layer | Choice | Rationale |
|---|---|---|
| Frontend | Single-file HTML/JS/CSS (index.html) | Current working system; no build step |
| Backend | Supabase (Postgres + Auth + Storage) | Already in use; handles RLS, real-time |
| Payments | ATH Móvil Business + Stripe | ATH Móvil = dominant in PR; Stripe = fallback |
| Charts | Chart.js v4 (CDN) | Already loaded; lightweight |
| Fonts | Google Fonts (Orbitron + Inter) | Brand consistency |
| Excel export | SheetJS xlsx v0.18 (CDN) | Client-side .xlsx without server |
| Tournament software | Stadium Compete (external) | FPRTM's existing draw/scoring tool |

**Supabase tables (current):**
- `Base de Datos` — player registry (Member ID, Name, Rating, New Rating, DOB, Sex, Club, Email, Address, Expiration Date)
- `insc_registro` — tournament registrations (member_id, torneo, categorias[], base, total, pagado, dob, sex, club)
- `partidos` — match results (torneo_id, jugador_a_id, jugador_b_id, ganador_id, ratings before/after, fecha, notas)
- `club_change_requests` — transfer requests (member_id, current_club, new_club, status)
- `app_settings` — feature flags (inscripciones_open, torneo_archivado)
- `photo_requests` — player photo submissions
- `membership_requests` — new membership applications

**Auth:** Supabase Auth (email/password). Admin role gated by `currentUser` presence. Public pages (spectator, ratings) require no login.

---

## 11. Security & Privacy

- RLS (Row Level Security) enabled on all Supabase tables.
- Admin operations use authenticated JWT session, never the anon key.
- Player DOB and personal data only exposed to authenticated admins in exports.
- Payment webhooks validated server-side (Stripe signature, ATH Móvil token).
- No PII stored in localStorage; only feature flags and display preferences.

---

## 12. Open Questions

| # | Question | Owner | Due |
|---|---|---|---|
| 1 | What is the exact ATH Móvil Business webhook format? | FPRTM + Dev | Before payment sprint |
| 2 | Should referees log in or use a PIN per table? | FPRTM board | Before live scoring sprint |
| 3 | Is there a rating floor (e.g., minimum 100)? | Dirección Técnica | Before rating sprint |
| 4 | Should Sub-21 + 1 Rating combo rule apply to all future tournaments or only Ceiba Open? | Dirección Técnica | Next tournament planning |
| 5 | Will Kileaaa replace Stadium Compete draws or integrate alongside it? | FPRTM board | Before v2 planning |
| 6 | What membership tiers exist (Junior, Senior, Lifetime)? | FPRTM board | Before membership sprint |
| 7 | Language toggle — detect browser language or always default to Spanish? | Product | Design sprint |
| 8 | Should spectator bracket view require account creation? | Product | Design sprint |

---

## 13. Milestones

| Phase | Scope | Target |
|---|---|---|
| **v1 — Foundation** | Registration, payments (Stripe), memberships, rating upload, admin reports, announcements | Current (shipped) |
| **v1.5 — ATH Móvil** | Native ATH Móvil payment flow, webhook handling | Q3 2026 |
| **v2 — Live** | Live scoring (referee entry), table assignment, spectator bracket view | Q4 2026 |
| **v2.5 — Rankings** | Full ratings leaderboard, player profiles, rating history chart | Q1 2027 |
| **v3 — PWA** | Installable app, offline support, push notifications | Q2 2027 |

---

## 14. Appendix

### A. FPRTM Rating Levels Guide

| Level | Rating | Description |
|---|---|---|
| Principiante | < 800 | Just starting competitive play |
| Intermedio Bajo | 800–1199 | Developing consistency |
| Intermedio | 1200–1499 | Club-level competitive |
| Intermedio Alto | 1500–1599 | Strong local player |
| Avanzado | 1600–1749 | Category-level competition |
| Semi-Elite | 1750–1899 | Top island-level player |
| Elite | 1900+ | National representation level |

### B. Glossary

| Term | Definition |
|---|---|
| FPRTM | Federación Puertorriqueña de Tenis de Mesa |
| ATH Móvil | Puerto Rico's dominant mobile payment platform |
| Stadium Compete | Third-party tournament bracket/draw software used by FPRTM |
| Dirección Técnica | FPRTM's technical direction / coaching committee |
| Retired | Match result where a player cannot continue; no rating change for either player |
| Default / W/O | Player fails to appear or is disqualified; loser loses rating points |
| torneo_archivado | System flag that switches the inscription tab from active to closed/thank-you state |
| Kileaaa | Puerto Rican colloquial for "to play/compete" — the platform name |
