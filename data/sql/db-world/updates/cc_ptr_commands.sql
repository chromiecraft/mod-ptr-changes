UPDATE `command` SET `security` = 0 WHERE `name` IN (
'additem set', 'additem', 'appear', 'aura', 'bags clear', 'bags', 'cast back', 'cast dest', 'cast dist',
'cast self', 'cast', 'cfbg race', 'cfbg', 'cheat casttime', 'cheat cooldown', 'cheat explore', 'cheat god',
'cheat power', 'cheat taxi', 'cheat waterwalk', 'cheat', 'combatstop', 'cooldown', 'damage', 'die', 'dismount',
'distance', 'gm fly', 'gobject activate', 'gobject add temp', 'gobject respawn', 'gps', 'help', 'levelup', 'mailbox',
'maxskill', 'npc add temp', 'npc info', 'recall', 'respawn', 'save', 'server info', 'summon', 'teleport', 'unaura', 'unlearn');

UPDATE `command` SET `security` = 0 WHERE `name` LIKE "debug%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "event%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "gear%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "go%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "honor%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "instance%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "learn%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "list%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "lookup%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "modify%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "morph%";
UPDATE `command` SET `security` = 0 WHERE `name` LIKE "quest%";
