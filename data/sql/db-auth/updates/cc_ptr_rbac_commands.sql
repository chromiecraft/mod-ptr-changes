-- ============================================================================
-- PTR command access via RBAC (replaces cc_ptr_commands.sql)
--
-- AzerothCore PR #24641 (RBAC) replaces `command.security`-based gating with
-- the rbac_* tables in the auth DB. Lowering `command.security` no longer has
-- any effect on commands whose registered RBAC permission ID is >= 200, which
-- is every core command after the port. The old approach in
-- cc_ptr_commands.sql (DELETE FROM command + re-insert with lowered values,
-- followed by an UPDATE block setting `security = 0` for ~200 commands and
-- LIKE patterns for whole prefixes) is now a silent no-op.
--
-- This file defines a dedicated RBAC role, "PTR Player" (perm id 1000),
-- containing every command-permission grant the old PTR file expressed via
-- `command.security = 0`. The role is then linked into role 199
-- ("Player Commands"), which is inherited by role 195 ("Sec Level Player"),
-- which is the default for secId 0 accounts. Net effect: any account at
-- sec level 0 (player) on PTR realms gains the commands listed below.
--
-- Why a dedicated role rather than linking each perm to 199 directly:
--   * The grant set is large (~131 perms). Bundling them under one role
--     keeps the linkage table readable and lets a future operator audit
--     PTR-specific exposure with a single `SELECT linkedId FROM
--     rbac_linked_permissions WHERE id = 1000`.
--   * Revoking PTR access on a non-PTR realm is a single-row delete:
--     `DELETE FROM rbac_linked_permissions WHERE id = 199 AND linkedId =
--     1000`, leaving the per-perm grant rows intact for re-enabling later.
--
-- Why id = 1000:
--   * PR #24641 reserves 1-913 for core perms and 100000+ for module perms
--     (auto-allocated via the `module_rbac_permissions` table). 1000 is in
--     the unused gap, far enough below the module range to avoid future
--     core-perm collisions while staying in the human-friendly low range.
--   * If a core perm is ever added at id 1000 upstream, this file's
--     idempotency block will need its role id updated; flag this on review
--     of any later #24641 follow-up that grows the core perm range.
--
-- Permission IDs are sourced from PR #24641's auth migration
-- (rev_1770173499134350791.sql) and verified against the cs_*.cpp command
-- registration tables on commit ddd721e.
--
-- 131 unique RBAC permissions covering ~206 of the ~214 commands the old
-- file lowered to sec 0. The 8 commands that could not be mapped are listed
-- at the bottom of this file with their reasons.
-- ============================================================================

-- Idempotency: drop the PTR Player role's existing links and the role's
-- inbound link from Player Commands, then re-create from scratch. The
-- ON DELETE CASCADE on rbac_linked_permissions.id removes outgoing links
-- when the role row is deleted; we still clear the inbound (199 -> 1000)
-- link explicitly because the FK is on `linkedId`, not `id`.
DELETE FROM `rbac_linked_permissions` WHERE `id` = 199 AND `linkedId` = 1000;
DELETE FROM `rbac_permissions` WHERE `id` = 1000;

-- Define the role.
INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
(1000, 'Role: PTR Player');

-- Wire the role into the player command role so secId 0 inherits it.
INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
(199, 1000); -- Player Commands -> PTR Player

-- All command perms granted by the PTR Player role.
INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
-- Spells & casting
(1000, 267), -- cast
(1000, 268), -- cast back
(1000, 269), -- cast dist
(1000, 270), -- cast self
(1000, 272), -- cast dest
-- Character utilities
(1000, 274), -- character customize
(1000, 275), -- character changefaction
(1000, 276), -- character changerace
(1000, 287), -- levelup
-- Cheat suite
(1000, 292), -- cheat casttime
(1000, 293), -- cheat cooldown
(1000, 294), -- cheat explore
(1000, 295), -- cheat god
(1000, 296), -- cheat power
(1000, 298), -- cheat taxi
(1000, 299), -- cheat waterwalk
-- Debug (BROAD): PR #24641 collapses every `.debug *` subcommand onto a
-- single permission, RBAC_PERM_COMMAND_DEBUG (300). Granting it exposes
-- ~50 subcommands including potentially harmful ones such as
-- `.debug send opcode`, `.debug Mod32Value`, `.debug setitemvalue`,
-- `.debug setbit`, `.debug setvalue`, `.debug spawnvehicle`. Acceptable
-- for PTR, NOT for production. Splitting this perm upstream is the
-- proper long-term fix.
(1000, 300), -- debug (and all subcommands)
-- Deserter
(1000, 343), -- deserter bg add
(1000, 344), -- deserter bg remove (also gates `bg remove all`)
(1000, 346), -- deserter instance add
(1000, 347), -- deserter instance remove (also gates `instance remove all`)
-- Event
(1000, 367), -- event info
(1000, 368), -- event activelist
(1000, 369), -- event start
(1000, 370), -- event stop
-- GM utilities
(1000, 373), -- gm fly
-- Go (perm 377 covers every `.go *` subcommand in cs_go.cpp)
(1000, 377), -- go (and creature/gameobject/graveyard/grid/quest/taxinode/ticket/trigger/xyz/zonexy)
-- GameObject
(1000, 388), -- gobject activate
-- Honor
(1000, 409), -- honor add
(1000, 410), -- honor add kill
(1000, 411), -- honor update
-- Instance
(1000, 413), -- instance listbinds
(1000, 414), -- instance unbind
(1000, 415), -- instance stats
(1000, 416), -- instance savedata
(1000, 795), -- instance setbossstate
(1000, 796), -- instance getbossstate
-- Learn
(1000, 417), -- learn (also gates `learn all`)
(1000, 419), -- learn all my (also gates `learn all my pettalents`)
(1000, 420), -- learn all my class
(1000, 422), -- learn all my spells
(1000, 423), -- learn all my talents
(1000, 424), -- learn all gm
(1000, 425), -- learn all crafts
(1000, 426), -- learn all default
(1000, 427), -- learn all lang
(1000, 428), -- learn all recipes
(1000, 429), -- unlearn
-- List
(1000, 437), -- list creature
(1000, 438), -- list item
(1000, 439), -- list object
(1000, 440), -- list auras (also gates `list auras id`/`list auras name`)
-- Lookup
(1000, 442), -- lookup
(1000, 443), -- lookup area (also gates `lookup gobject`)
(1000, 444), -- lookup creature
(1000, 445), -- lookup event
(1000, 446), -- lookup faction
(1000, 447), -- lookup item (also gates `lookup item set`)
(1000, 449), -- lookup object
(1000, 450), -- lookup quest
(1000, 451), -- lookup player
(1000, 452), -- lookup player ip
(1000, 453), -- lookup player account
(1000, 454), -- lookup player email
(1000, 455), -- lookup skill
(1000, 456), -- lookup spell
(1000, 457), -- lookup spell id
(1000, 458), -- lookup taxinode
(1000, 459), -- lookup teleport (renamed `lookup tele` in #24641)
(1000, 460), -- lookup title
(1000, 461), -- lookup map
-- Items
(1000, 488), -- additem
(1000, 489), -- additem set
(1000, 777), -- mailbox
(1000, 892), -- opendoor
(1000, 897), -- gear repair
(1000, 898), -- gear stats
-- Player state
(1000, 490), -- appear
(1000, 491), -- aura
(1000, 494), -- combatstop
(1000, 497), -- cooldown
(1000, 498), -- damage
(1000, 500), -- die
(1000, 501), -- dismount
(1000, 502), -- distance
(1000, 505), -- gps
(1000, 507), -- help
(1000, 513), -- maxskill
(1000, 520), -- recall
(1000, 522), -- respawn
(1000, 523), -- revive
(1000, 525), -- save
(1000, 526), -- setskill
(1000, 529), -- unaura
-- Morph
(1000, 542), -- morph (also gates `morph mount`/`morph reset`/`morph target`)
-- Modify
(1000, 544), -- modify
(1000, 545), -- modify arenapoints
(1000, 546), -- modify bit
(1000, 547), -- modify drunk
(1000, 548), -- modify energy
(1000, 549), -- modify faction
(1000, 550), -- modify gender
(1000, 551), -- modify honor
(1000, 552), -- modify hp
(1000, 553), -- modify mana
(1000, 554), -- modify money
(1000, 555), -- modify mount
(1000, 556), -- modify phase
(1000, 557), -- modify rage
(1000, 558), -- modify reputation
(1000, 559), -- modify runicpower
(1000, 560), -- modify scale
(1000, 561), -- modify speed
(1000, 562), -- modify speed all
(1000, 563), -- modify speed backwalk
(1000, 564), -- modify speed fly
(1000, 565), -- modify speed walk
(1000, 566), -- modify speed swim
(1000, 567), -- modify spell
(1000, 568), -- modify standstate
(1000, 569), -- modify talentpoints
-- NPC inspection
(1000, 593), -- npc info (also gates `npc guid`)
(1000, 601), -- npc tame
-- Quest
(1000, 602), -- quest (also gates `quest status`)
(1000, 603), -- quest add
(1000, 604), -- quest complete
(1000, 605), -- quest remove
(1000, 606), -- quest reward
-- Misc
(1000, 716), -- reset talents
(1000, 725), -- server info
(1000, 737); -- teleport (renamed `tele` in #24641)

-- ============================================================================
-- NOT GRANTED -- design notes for reviewers
-- ============================================================================
-- The original cc_ptr_commands.sql lowered the following commands but they
-- are deliberately or unavoidably omitted here:
--
--   gobject respawn
--     -> No matching perm in PR #24641. cs_gobject.cpp does not register a
--        `respawn` subcommand under `gobject`. Use top-level `.respawn`
--        (perm 522, granted above) if a player-accessible respawn is needed.
--
--   reload npc_trainer, reload spell_proc_event
--     -> No matching perm in PR #24641. The underlying reload subcommands
--        appear to have been dropped/renamed during the TC port. Re-evaluate
--        once #24641 stabilises.
--
--   bags, bags clear
--     -> No matching perm in PR #24641. These look like ChromieCraft custom
--        commands not present in upstream AzerothCore. If they exist as
--        custom modules, grant them inside the owning module via
--        module_rbac_permissions.
--
--   cfbg, cfbg race, transmog * (5 cmds), weekendxp * (2 cmds),
--   anticheat * (8 cmds)
--     -> All from external modules (mod-cfbg, mod-transmog, mod-weekendxp,
--        mod-anticheat). Under PR #24641 each module must register its own
--        permissions via the new `module_rbac_permissions` table and use
--        AccountMgr::GetModulePermission(module, localId) at command
--        registration time. Granting them here would require knowing the
--        runtime-allocated `global_id` for each module's perms, which is
--        not stable across deployments. The right place for these grants
--        is inside each module after it adopts module-RBAC.
--
--   template apply, template list (sec 0 in old file via UPDATE block)
--     -> The original file already INSERTed these explicitly with sec 0
--        (lines 626-630). They are AzerothCore character-template module
--        commands; if that module is loaded on PTR, grant them inside the
--        template module via module_rbac_permissions.
-- ============================================================================
