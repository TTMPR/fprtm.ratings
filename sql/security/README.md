# Seguridad FPTM / Kileaaa — baseline del 20 de octubre de 2026

El registro oficial de la Federación en Supabase sigue siendo el **único registro de atletas, Member ID, rating y membresías**. Kileaaa enlaza perfiles; nunca replica el registro de identidad ni modifica ratings sin autorización.

## Migraciones aplicadas a producción (registro Supabase)

Migraciones versionadas del 20 de octubre: 
- `secure_membership_requests_and_privileged_functions_20261020`
- `restrict_private_athlete_and_club_requests_20261020`
- `restrict_legacy_admin_rls_to_approved_owner_20261020`
- `restrict_remaining_admin_mutations_by_uid_20261020`
- `revoke_dangerous_default_table_privileges_20261020`
- `protect_official_athlete_pii_with_public_projection_20261020`
- `require_admin_rls_for_existing_record_rpc_mutations_20261020`
- `limit_public_storage_uploads_and_owner_writes_20261020`
- `atomic_one_time_player_registration_functions_20261020`
- `close_direct_anonymous_registration_tables_20261020`
- `block_public_registration_payment_forgery_and_updates_20261020`
- `public_tournament_read_projection_without_personal_fields_20261020`
- `secure_public_tournament_team_views_as_invoker_20261020`
- `validate_anonymous_club_and_photo_proposals_20261020`
- `make_public_athlete_and_partner_views_invoker_via_private_safe_projections_20261020`
- `move_seven_public_privileged_rpcs_to_private_security_schema_20261020`
- `quarantine_public_pending_player_photos_and_minors_20261020`

**Important:** `sql/schema/090_rls_current_snapshot.sql` and legacy `create_*.sql` files reflect historical setup and MUST NOT be reapplied alone against production. They contain policies superseded by these migrations. Review and reconcile the full migrations before provisioning a replacement database.

## Required security checks

Run `sql/security/verify_access_controls_20261020.sql` in the Supabase SQL editor under a privileged database account. It fails if the direct public athlete table, membership requests, one-time tokens or tournament PII become visible, if safe public views are no longer security-invoker, if public SECURITY DEFINER RPCs reappear, or if the pending player-photo bucket becomes public.

Validated on 2026-10-20: `security_baseline=PASS`. Public-query smoke counts: 313 official active players, 2 partner ads, 744 tournament registrations and 57 teams. These counts are factual snapshot values, not ongoing invariants.

## Privacy / public photo rollout restriction

All 58 athlete images currently remain in the **private** `player-photos` bucket; 49 review records were approved (21 flagged minors), 9 rejected (3 flagged minors). No images were deleted. Because all objects were placed in a `pending/` prefix in the old public bucket, previously approved portraits are temporarily hidden too. Do not re-enable the bucket's `public` flag.

Before reopening:
1. Create a separate public **approved-only** bucket, after confirming consent for minors and data-retention policy.
2. Use authenticated administrative Storage APIs to copy only reviewed/approved objects, not rejected or pending ones.
3. Update approved `photo_requests.photo_url` and public `api_jugadores` photo URLs to the new bucket, only after verifying each file.
4. Enable a distinct private upload bucket with MIME, size and rate limits; all submissions require admin approval.
5. Verify anonymous users cannot read pending/rejected images or storage object lists.

## Remaining controls / no-production-v2 gate

- One Supabase Auth advisory remains: leaked-password protection must be enabled under project Authentication settings, if the account plan supports it. Also require strong admin credentials and MFA.
- Firebase `firestore.rules` in `TTMPR/kileaaa.com` is only source code until deployed to the actual Firebase project. Backend rules must be simulated against player/admin access before production.
- Railway v2 preview and GitHub Actions security tests must pass. `kileaaa.com` main is not the v2 release target yet.
- Legacy individual tournament direct anonymous insert still requires server-authoritative fee and identity validation before registration windows are reopened. An anonymous `pagado=true` update is already denied.
- Membership enrollment ATH Móvil `/FPRTM` remains manual with evidence sent to Joel Vega; do not mark payments confirmed without provider or human verification.
- GitHub Pages publishing does not validate business operations; complete real browser smoke tests with an isolated test account.

This document is a living operational safety checklist, not a third-party security certification or legal compliance attestation.
