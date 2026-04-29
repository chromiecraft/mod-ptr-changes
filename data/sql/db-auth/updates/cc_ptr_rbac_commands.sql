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
-- This file expresses the same intent (expose those commands to PTR players)
-- by linking the relevant command permissions to role 199
-- ("Player Commands"), which is inherited by role 195 ("Sec Level Player"),
-- which is the default role for secId 0 accounts. Net effect: any account at
-- sec level 0 (player) on PTR realms gains the commands listed below.
--
-- Permission IDs are sourced from PR #24641's auth migration
-- (rev_1770173499134350791.sql) and verified against the cs_*.cpp command
-- registration tables on commit ddd721e.
--
-- 131 unique RBAC permissions covering ~206 of the ~214 commands the old
-- file lowered to sec 0. The 8 commands that could not be mapped are listed
-- at the bottom of this file with their reasons.
-- ============================================================================

-- Idempotency: clear any prior PTR-specific player-command grants in the
-- ranges this file manages, then re-insert. Keeps re-runs and rebases clean.
DELETE FROM `rbac_linked_permissions` WHERE `id` = 199 AND `linkedId` IN (
    267,268,269,270,272,
    274,275,276,
    287,292,293,294,295,296,298,299,
    300,
    343,344,346,347,
    367,368,369,370,
    373,377,388,
    409,410,411,
    413,414,415,416,
    417,419,420,422,423,424,425,426,427,428,429,
    437,438,439,440,
    442,443,444,445,446,447,449,450,451,452,453,454,455,456,457,458,459,460,461,
    488,489,490,491,494,497,498,500,501,502,
    505,507,513,520,522,523,525,526,529,
    542,544,545,546,547,548,549,550,551,552,553,554,555,556,557,558,559,560,
    561,562,563,564,565,566,567,568,569,
    593,601,602,603,604,605,606,
    716,725,737,777,
    795,796,
    892,897,898
);

INSERT INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
-- Spells & casting
(199, 267), -- cast
(199, 268), -- cast back
(199, 269), -- cast dist
(199, 270), -- cast self
(199, 272), -- cast dest
-- Character utilities
(199, 274), -- character customize
(199, 275), -- character changefaction
(199, 276), -- character changerace
(199, 287), -- levelup
-- Cheat suite
(199, 292), -- cheat casttime
(199, 293), -- cheat cooldown
(199, 294), -- cheat explore
(199, 295), -- cheat god
(199, 296), -- cheat power
(199, 298), -- cheat taxi
(199, 299), -- cheat waterwalk
-- Debug (BROAD): PR #24641 collapses every `.debug *` subcommand onto a
-- single permission, RBAC_PERM_COMMAND_DEBUG (300). Granting it exposes
-- ~50 subcommands including potentially harmful ones such as
-- `.debug send opcode`, `.debug Mod32Value`, `.debug setitemvalue`,
-- `.debug setbit`, `.debug setvalue`, `.debug spawnvehicle`. Acceptable
-- for PTR, NOT for production. Splitting this perm upstream is the
-- proper long-term fix.
(199, 300), -- debug (and all subcommands)
-- Deserter
(199, 343), -- deserter bg add
(199, 344), -- deserter bg remove (also gates `bg remove all`)
(199, 346), -- deserter instance add
(199, 347), -- deserter instance remove (also gates `instance remove all`)
-- Event
(199, 367), -- event info
(199, 368), -- event activelist
(199, 369), -- event start
(199, 370), -- event stop
-- GM utilities
(199, 373), -- gm fly
-- Go (perm 377 covers every `.go *` subcommand in cs_go.cpp)
(199, 377), -- go (and creature/gameobject/graveyard/grid/quest/taxinode/ticket/trigger/xyz/zonexy)
-- GameObject
(199, 388), -- gobject activate
-- Honor
(199, 409), -- honor add
(199, 410), -- honor add kill
(199, 411), -- honor update
-- Instance
(199, 413), -- instance listbinds
(199, 414), -- instance unbind
(199, 415), -- instance stats
(199, 416), -- instance savedata
(199, 795), -- instance setbossstate
(199, 796), -- instance getbossstate
-- Learn
(199, 417), -- learn (also gates `learn all`)
(199, 419), -- learn all my (also gates `learn all my pettalents`)
(199, 420), -- learn all my class
(199, 422), -- learn all my spells
(199, 423), -- learn all my talents
(199, 424), -- learn all gm
(199, 425), -- learn all crafts
(199, 426), -- learn all default
(199, 427), -- learn all lang
(199, 428), -- learn all recipes
(199, 429), -- unlearn
-- List
(199, 437), -- list creature
(199, 438), -- list item
(199, 439), -- list object
(199, 440), -- list auras (also gates `list auras id`/`list auras name`)
-- Lookup
(199, 442), -- lookup
(199, 443), -- lookup area (also gates `lookup gobject`)
(199, 444), -- lookup creature
(199, 445), -- lookup event
(199, 446), -- lookup faction
(199, 447), -- lookup item (also gates `lookup item set`)
(199, 449), -- lookup object
(199, 450), -- lookup quest
(199, 451), -- lookup player
(199, 452), -- lookup player ip
(199, 453), -- lookup player account
(199, 454), -- lookup player email
(199, 455), -- lookup skill
(199, 456), -- lookup spell
(199, 457), -- lookup spell id
(199, 458), -- lookup taxinode
(199, 459), -- lookup teleport (renamed `lookup tele` in #24641)
(199, 460), -- lookup title
(199, 461), -- lookup map
-- Items
(199, 488), -- additem
(199, 489), -- additem set
(199, 777), -- mailbox
(199, 892), -- opendoor
(199, 897), -- gear repair
(199, 898), -- gear stats
-- Player state
(199, 490), -- appear
(199, 491), -- aura
(199, 494), -- combatstop
(199, 497), -- cooldown
(199, 498), -- damage
(199, 500), -- die
(199, 501), -- dismount
(199, 502), -- distance
(199, 505), -- gps
(199, 507), -- help
(199, 513), -- maxskill
(199, 520), -- recall
(199, 522), -- respawn
(199, 523), -- revive
(199, 525), -- save
(199, 526), -- setskill
(199, 529), -- unaura
-- Morph
(199, 542), -- morph (also gates `morph mount`/`morph reset`/`morph target`)
-- Modify
(199, 544), -- modify
(199, 545), -- modify arenapoints
(199, 546), -- modify bit
(199, 547), -- modify drunk
(199, 548), -- modify energy
(199, 549), -- modify faction
(199, 550), -- modify gender
(199, 551), -- modify honor
(199, 552), -- modify hp
(199, 553), -- modify mana
(199, 554), -- modify money
(199, 555), -- modify mount
(199, 556), -- modify phase
(199, 557), -- modify rage
(199, 558), -- modify reputation
(199, 559), -- modify runicpower
(199, 560), -- modify scale
(199, 561), -- modify speed
(199, 562), -- modify speed all
(199, 563), -- modify speed backwalk
(199, 564), -- modify speed fly
(199, 565), -- modify speed walk
(199, 566), -- modify speed swim
(199, 567), -- modify spell
(199, 568), -- modify standstate
(199, 569), -- modify talentpoints
-- NPC inspection
(199, 593), -- npc info (also gates `npc guid`)
(199, 601), -- npc tame
-- Quest
(199, 602), -- quest (also gates `quest status`)
(199, 603), -- quest add
(199, 604), -- quest complete
(199, 605), -- quest remove
(199, 606), -- quest reward
-- Misc
(199, 716), -- reset talents
(199, 725), -- server info
(199, 737); -- teleport (renamed `tele` in #24641)

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
