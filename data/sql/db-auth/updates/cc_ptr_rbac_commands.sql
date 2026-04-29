-- ============================================================================
-- PTR command access via RBAC (replaces cc_ptr_commands.sql)
--
-- AzerothCore PR #24641 (RBAC) replaces `command.security`-based gating with
-- the rbac_* tables in the auth DB. Lowering `command.security` no longer has
-- any effect on commands whose registered RBAC permission ID is >= 200, which
-- is every core command after the port. The old approach in
-- cc_ptr_commands.sql (DELETE FROM command + re-insert with lowered values)
-- is now a no-op for gating purposes.
--
-- This file expresses the same intent (expose selected GM/Mod commands to
-- PTR players) by linking the relevant command permissions to role 199
-- ("Player Commands"), which is inherited by role 195 ("Sec Level Player"),
-- which is the default role for secId 0 accounts. Net effect: any account at
-- sec level 0 (player) on PTR realms gains the commands listed below.
--
-- Permission IDs are sourced from PR #24641's auth migration
-- (rev_1770173499134350791.sql).
-- ============================================================================

-- Idempotency: clear any prior PTR-specific player command grants in the
-- ranges we manage, then re-insert. Keeps re-runs and rebases clean.
DELETE FROM `rbac_linked_permissions` WHERE `id` = 199 AND `linkedId` IN (
    258, 259, 260, 261, 262, -- bf start/stop/switch/timer/enable
    593,                     -- npc info (also gates `npc guid`)
    737                      -- tele (the `.teleport` of the pre-RBAC tree)
);

INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
-- Battlefield commands: stock perms restrict to GM (sec 3); PTR exposes to
-- players for testing Wintergrasp / Tol Barad style mechanics.
(199, 258), -- Command: bf start
(199, 259), -- Command: bf stop
(199, 260), -- Command: bf switch
(199, 261), -- Command: bf timer
(199, 262), -- Command: bf enable
-- NPC inspection: the .npc info and .npc guid commands share perm 593 in
-- PR #24641 (cs_npc.cpp). Granting 593 covers both, matching the original
-- cc_ptr_commands.sql intent of `npc guid` / `npc info` at low sec.
(199, 593), -- Command: npc info (also gates `npc guid`)
-- Teleport: PR #24641 registers the command as `.tele` (perm 737) rather
-- than the pre-RBAC `.teleport`. This grant is the RBAC equivalent of
-- lowering `teleport` to sec 1 in the old file.
(199, 737); -- Command: tele

-- ============================================================================
-- NOT GRANTED — design notes for reviewers
-- ============================================================================
-- The original cc_ptr_commands.sql also lowered the following commands. They
-- are deliberately omitted here:
--
--   cache info, cache refresh, debug hostile, debug play cinematic,
--   debug play movie, debug play sound
--     -> All map to a single perm `RBAC_PERM_COMMAND_DEBUG` (300) in PR
--        #24641. Granting 300 to players would expose every `.debug *`
--        subcommand (~80+ commands, including dangerous ones such as
--        `.debug send opcode`). The right upstream fix is to split the
--        debug perm; until that lands, leave debug commands gated to GM.
--
--   gobject respawn
--     -> No matching perm in PR #24641. cs_gobject.cpp does not register a
--        `respawn` subcommand under `gobject`. Use the top-level `.respawn`
--        (perm 522) if a player-accessible respawn is needed.
--
--   reload npc_trainer, reload spell_proc_event
--     -> Neither has a corresponding perm in PR #24641's auth migration;
--        the underlying reload subcommands appear to have been dropped or
--        renamed during the port. Re-evaluate once #24641 stabilises.
--
--   anticheat *, cfbg, cfbg race, transmog *, weekendxp *
--     -> These are commands registered by external modules
--        (mod-anticheat, mod-cfbg, mod-transmog, mod-weekendxp). Under
--        PR #24641 each module must register its own permissions via the
--        new `module_rbac_permissions` table and use
--        `AccountMgr::GetModulePermission(module, localId)` at command
--        registration time. Granting them here would require knowing the
--        runtime-allocated `global_id` for each module's perms, which is
--        not stable across deployments. The right place for these grants
--        is inside each module after it adopts module-RBAC.
-- ============================================================================
