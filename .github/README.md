# PTR Changes

[English](README.md) 

# About

This module holds PTR commands and PTR specific changes, like temp spawns, events, etc.

# Command audit log

Every in-game command is logged before it runs, including commands from player accounts (core only logs staff
commands). Each line has the typed text, the resolved command (abbreviations expanded), character name and guid,
account id, position, map, area, zone and the selected unit. Refused commands are prefixed with `REFUSED`.

The logger is set up before module configs load, so add these lines to PTR's `worldserver.conf`:

```
Appender.PTRCommands=2,4,1,PTR_Commands.log,a
Logger.module.ptr.commands=4,PTRCommands
```

Without them the lines fall back to `Logger.module` (Console and Server.log at the default level).

# Command guard

PTR player accounts (security level 0, RBAC role 1000 on realm 2) can't use the testing commands on other players.
Commands still work on yourself and on creatures. Staff accounts are not restricted.

- Selection: refused when the selected unit is another player, or a pet, guardian, charmed unit or vehicle that
  belongs to or carries another player. `.die`, `.damage`, `.aura`, `.unaura`, `.cast`, `.cast self`, `.cast dest`,
  `.modify *`, `.morph *`, `.debug *`, `.learn`, `.unlearn`, `.setskill`, `.additem`, `.additem set`, `.levelup`,
  `.recall`, `.combatstop`, `.quest *`, `.deserter * add`, `.instance unbind`, `.character customize/changerace/changefaction`,
  `.player learn/unlearn`, `.cheat taxi`, `.gm fly`, `.lookup player ip`.
- Name argument: refused when the command names another character, online or offline (`.additem`, `.levelup`,
  `.recall`, `.combatstop`, `.quest *`, `.deserter * add`, `.instance unbind`, `.instance setbossstate`,
  `.reset talents`, `.character *`, `.player learn/unlearn`).
- Spells: `.cast` (all variants) and `.aura` refuse spells with a harmful effect that picks its own targets (area,
  cone, nearby, chain, area auras, persistent area auras), following triggered and linked spells.
- `.debug setbit` is disabled for players: it writes any field index unchecked and an out-of-range index crashes the
  worldserver.

# Updates

The PTR updates at 0AM and 0PM daily, any changes applied to this module will go live once it restarts after the update is done.
