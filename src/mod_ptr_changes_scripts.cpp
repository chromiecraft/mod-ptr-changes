/*
 * Copyright (C) 2016+ AzerothCore <www.azerothcore.org>, released under GNU AGPL v3 license: https://github.com/azerothcore/azerothcore-wotlk/blob/master/LICENSE-AGPL3
 */

#include "AccountMgr.h"
#include "CharacterCache.h"
#include "Chat.h"
#include "ChatCommand.h"
#include "ChatCommandArgs.h"
#include "ChatCommandTags.h"
#include "DBCStores.h"
#include "Log.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SpellInfo.h"
#include "SpellMgr.h"
#include "StringFormat.h"
#include "Util.h"
#include "Vehicle.h"
#include "World.h"
#include <array>

using namespace Acore::ChatCommands;

namespace
{
    // Matches no command name, so autocompletion stops on it and returns "<canonical command> <args> <sentinel>".
    constexpr std::string_view ResolveSentinel = "\x1F";
    constexpr uint8 MaxTriggerDepth = 3;

    enum GuardFlags : uint8
    {
        GUARD_SELECTION = 0x01, // the selected unit must not be another player or something another player controls
        GUARD_VICTIM    = 0x02, // same check on the selected creature's victim
        GUARD_SPELL     = 0x04, // the first argument is a spell that must not hit units in an area
        GUARD_DISABLED  = 0x08, // never allowed for player accounts
    };

    using PlayerArgCheck = bool(*)(ChatHandler const& handler, Player const* invoker, std::string_view args);

    struct GuardedCommand
    {
        std::string_view Name;
        uint8 Flags;
        PlayerArgCheck NamesOtherPlayer;
    };

    // Parses args with the handler's own argument types, so optional-argument backtracking matches the real command.
    template <std::size_t PlayerArg, typename... Args>
    bool ArgsNameOtherPlayer(ChatHandler const& handler, Player const* invoker, std::string_view args)
    {
        using Tuple = std::tuple<ChatHandler*, Args...>;
        Tuple parsed;
        if (!Acore::Impl::ChatCommands::ConsumeFromOffset<Tuple, 1>(parsed, &handler, args))
            return false;

        Optional<PlayerIdentifier> const& player = std::get<PlayerArg>(parsed);
        return player && player->GetGUID() != invoker->GetGUID();
    }

    // The deserter handlers take a plain name and treat it as the duration when no character has that name.
    bool DeserterArgsNameOtherPlayer(ChatHandler const& handler, Player const* invoker, std::string_view args)
    {
        using Tuple = std::tuple<ChatHandler*, Optional<std::string>, Optional<std::string>>;
        Tuple parsed;
        if (!Acore::Impl::ChatCommands::ConsumeFromOffset<Tuple, 1>(parsed, &handler, args))
            return false;

        Optional<std::string> name = std::get<1>(parsed);
        if (!name || !normalizePlayerName(*name))
            return false;

        ObjectGuid const guid = sCharacterCache->GetCharacterGuidByName(*name);
        return guid && guid != invoker->GetGUID();
    }

    constexpr PlayerArgCheck PlayerFirst = &ArgsNameOtherPlayer<1, Optional<PlayerIdentifier>>;
    constexpr PlayerArgCheck QuestThenPlayer = &ArgsNameOtherPlayer<2, Quest const*, Optional<PlayerIdentifier>>;

    // Longest name wins, so an entry also covers its subcommands unless a longer entry (flags 0 to exempt) overrides it.
    // Entries that parse arguments must name the exact command, or the subcommand token would be read as an argument.
    constexpr auto GuardedCommands = std::to_array<GuardedCommand>(
    {
        { "additem",                GUARD_SELECTION, &ArgsNameOtherPlayer<1, Optional<PlayerIdentifier>, ItemTemplate const*, Optional<int32>> },
        { "additem set",            GUARD_SELECTION, nullptr },
        { "aura",                   GUARD_SELECTION | GUARD_SPELL, nullptr },
        { "aura stack",             GUARD_SELECTION | GUARD_SPELL, nullptr },
        { "cast",                   GUARD_SELECTION | GUARD_SPELL, nullptr },
        { "cast back",              GUARD_SPELL, nullptr },
        { "cast dest",              GUARD_SELECTION | GUARD_SPELL, nullptr },
        { "cast dist",              GUARD_SPELL, nullptr },
        { "cast self",              GUARD_SELECTION | GUARD_SPELL, nullptr },
        { "cast target",            GUARD_SELECTION | GUARD_VICTIM | GUARD_SPELL, nullptr },
        { "character changefaction", GUARD_SELECTION, PlayerFirst },
        { "character changerace",   GUARD_SELECTION, PlayerFirst },
        { "character customize",    GUARD_SELECTION, PlayerFirst },
        { "cheat taxi",             GUARD_SELECTION, nullptr },
        { "combatstop",             GUARD_SELECTION, PlayerFirst },
        { "damage",                 GUARD_SELECTION, nullptr },
        { "debug",                  GUARD_SELECTION, nullptr },
        { "debug setbit",           GUARD_DISABLED, nullptr },
        { "deserter bg add",        GUARD_SELECTION, &DeserterArgsNameOtherPlayer },
        { "deserter instance add",  GUARD_SELECTION, &DeserterArgsNameOtherPlayer },
        { "die",                    GUARD_SELECTION, nullptr },
        { "gm fly",                 GUARD_SELECTION, nullptr },
        { "instance setbossstate",  0, &ArgsNameOtherPlayer<3, uint32, uint32, Optional<PlayerIdentifier>> },
        { "instance unbind",        GUARD_SELECTION, &ArgsNameOtherPlayer<3, Variant<uint16, EXACT_SEQUENCE("all")>, Optional<uint32>, Optional<PlayerIdentifier>> },
        { "learn",                  GUARD_SELECTION, nullptr },
        { "learn all",              0, nullptr },
        { "levelup",                GUARD_SELECTION, &ArgsNameOtherPlayer<1, Optional<PlayerIdentifier>, int16> },
        { "lookup player ip",       GUARD_SELECTION, nullptr },
        { "modify",                 GUARD_SELECTION, nullptr },
        { "morph",                  GUARD_SELECTION, nullptr },
        { "player learn",           GUARD_SELECTION, &ArgsNameOtherPlayer<1, Optional<PlayerIdentifier>, SpellInfo const*, Optional<EXACT_SEQUENCE("all")>> },
        { "player unlearn",         GUARD_SELECTION, &ArgsNameOtherPlayer<1, Optional<PlayerIdentifier>, SpellInfo const*, Optional<EXACT_SEQUENCE("all")>> },
        { "quest add",              GUARD_SELECTION, QuestThenPlayer },
        { "quest complete",         GUARD_SELECTION, QuestThenPlayer },
        { "quest remove",           GUARD_SELECTION, QuestThenPlayer },
        { "quest reward",           GUARD_SELECTION, QuestThenPlayer },
        { "quest status",           GUARD_SELECTION, QuestThenPlayer },
        { "recall",                 GUARD_SELECTION, PlayerFirst },
        { "reset talents",          0, PlayerFirst },
        { "setskill",               GUARD_SELECTION, nullptr },
        { "unaura",                 GUARD_SELECTION, nullptr },
        { "unlearn",                GUARD_SELECTION, nullptr },
    });

    // Resolves abbreviations (".ca s 1" -> "cast self 1") with the same tree walk and visibility checks that
    // TryExecuteCommand used, so the guard sees the command that is about to run. Empty when nothing matches.
    std::string ResolveCommandLine(ChatHandler const& handler, std::string_view cmdStr)
    {
        std::vector<std::string> const completions = GetAutoCompletionsFor(handler, Acore::StringFormat("{} {}", cmdStr, ResolveSentinel));
        if (completions.size() != 1 || !completions.front().ends_with(ResolveSentinel))
            return {};

        std::string line = completions.front();
        line.resize(line.size() - ResolveSentinel.size());
        while (!line.empty() && line.back() == ' ')
            line.pop_back();

        return line;
    }

    // Matches on token boundaries; args receives what follows the matched name.
    GuardedCommand const* FindGuardedCommand(std::string_view line, std::string_view& args)
    {
        GuardedCommand const* match = nullptr;
        for (GuardedCommand const& guarded : GuardedCommands)
        {
            if (!StringStartsWithI(line, guarded.Name))
                continue;

            if (line.size() > guarded.Name.size() && line[guarded.Name.size()] != ' ')
                continue;

            if (!match || guarded.Name.size() > match->Name.size())
                match = &guarded;
        }

        if (match)
        {
            args = line.substr(match->Name.size());
            while (!args.empty() && args.front() == ' ')
                args.remove_prefix(1);
        }

        return match;
    }

    bool AffectsOtherPlayer(Player const* invoker, Unit const* unit)
    {
        if (!unit)
            return false;

        if (unit->IsPlayer())
            return unit != invoker;

        if (Player const* controller = unit->GetAffectingPlayer())
            if (controller != invoker)
                return true;

        if (Vehicle const* vehicle = unit->GetVehicleKit())
            for (auto const& [seatId, seat] : vehicle->Seats)
                if (seat.Passenger.Guid.IsPlayer() && seat.Passenger.Guid != invoker->GetGUID())
                    return true;

        return false;
    }

    bool SelectionAffectsOtherPlayer(Player const* invoker)
    {
        // Player-selecting commands use FindConnectedPlayer, which reaches players on other maps too.
        ObjectGuid const selection = invoker->GetTarget();
        if (selection.IsPlayer())
            return selection != invoker->GetGUID();

        return AffectsOtherPlayer(invoker, invoker->GetSelectedUnit());
    }

    bool CanReachOtherUnits(SpellImplicitTargetInfo const& target)
    {
        switch (target.GetSelectionCategory())
        {
            case TARGET_SELECT_CATEGORY_NEARBY:
            case TARGET_SELECT_CATEGORY_CONE:
            case TARGET_SELECT_CATEGORY_AREA:
            case TARGET_SELECT_CATEGORY_TRAJ:
                return true;
            default:
                return false;
        }
    }

    // A harmful effect that picks its own targets (area, cone, nearby, chain, area or persistent aura) can hit
    // players who were never selected, including through triggered and linked spells.
    bool IsHarmfulToArea(SpellInfo const* spellInfo, uint8 depth = 0)
    {
        if (!spellInfo || depth > MaxTriggerDepth)
            return false;

        for (SpellEffectInfo const& effect : spellInfo->GetEffects())
        {
            if (!effect.IsEffect())
                continue;

            bool const reachesOthers = effect.IsAreaAuraEffect() || effect.IsEffect(SPELL_EFFECT_PERSISTENT_AREA_AURA)
                || effect.ChainTarget > 1 || CanReachOtherUnits(effect.TargetA) || CanReachOtherUnits(effect.TargetB);

            bool const harmful = !spellInfo->IsPositiveEffect(effect.EffectIndex) || effect.IsEffect(SPELL_EFFECT_APPLY_AREA_AURA_ENEMY)
                || effect.TargetA.GetCheckType() == TARGET_CHECK_ENEMY || effect.TargetB.GetCheckType() == TARGET_CHECK_ENEMY;

            if (reachesOthers && harmful)
                return true;

            if (effect.TriggerSpell && !effect.IsEffect(SPELL_EFFECT_LEARN_SPELL) && !effect.IsEffect(SPELL_EFFECT_LEARN_PET_SPELL)
                && IsHarmfulToArea(sSpellMgr->GetSpellInfo(effect.TriggerSpell), depth + 1))
                return true;
        }

        for (int32 linkType : { SPELL_LINK_CAST, SPELL_LINK_HIT, SPELL_LINK_AURA })
            if (std::vector<int32> const* linked = sSpellMgr->GetSpellLinked(linkType + int32(spellInfo->Id)))
                for (int32 linkedId : *linked)
                    if (linkedId > 0 && IsHarmfulToArea(sSpellMgr->GetSpellInfo(linkedId), depth + 1))
                        return true;

        return false;
    }

    // Returns the refusal message, or an empty string when the command may run.
    std::string_view CheckGuardedCommand(ChatHandler const& handler, Player const* invoker, std::string_view line)
    {
        std::string_view args;
        GuardedCommand const* guarded = FindGuardedCommand(line, args);
        if (!guarded)
            return {};

        if (guarded->Flags & GUARD_DISABLED)
            return "This command is disabled for players on the PTR.";

        if ((guarded->NamesOtherPlayer && guarded->NamesOtherPlayer(handler, invoker, args))
            || ((guarded->Flags & GUARD_SELECTION) && SelectionAffectsOtherPlayer(invoker)))
            return "You can't use this command on other players, their pets or their vehicles on the PTR.";

        if (guarded->Flags & GUARD_VICTIM)
            if (Unit const* selected = invoker->GetSelectedUnit())
                if (AffectsOtherPlayer(invoker, selected->GetVictim()))
                    return "You can't use this command on a creature fighting another player on the PTR.";

        if (guarded->Flags & GUARD_SPELL)
        {
            SpellInfo const* spellInfo = nullptr;
            if (Acore::Impl::ChatCommands::ArgInfo<SpellInfo const*>::TryConsume(spellInfo, &handler, args) && IsHarmfulToArea(spellInfo))
                return "Harmful area spells can't be used through commands on the PTR.";
        }

        return {};
    }

    void LogCommand(WorldSession const* session, Player const* player, std::string_view cmdStr, std::string_view line, std::string_view refusal)
    {
        LocaleConstant const locale = sWorld->GetDefaultDbcLocale();
        uint32 const areaId = player->GetAreaId();
        uint32 const zoneId = player->GetZoneId();
        AreaTableEntry const* area = sAreaTableStore.LookupEntry(areaId);
        AreaTableEntry const* zone = sAreaTableStore.LookupEntry(zoneId);
        Unit const* selected = player->GetSelectedUnit();

        LOG_INFO("module.ptr.commands", "{}Command: {} (resolved: {}) [Player: {} ({}) Account: {} X: {} Y: {} Z: {} Map: {} ({}) Area: {} ({}) Zone: {} ({}) Selected: {} ({})]",
            refusal.empty() ? "" : "REFUSED ", cmdStr, line.empty() ? "-" : line,
            player->GetName(), player->GetGUID().ToString(), session->GetAccountId(),
            player->GetPositionX(), player->GetPositionY(), player->GetPositionZ(),
            player->GetMapId(), player->FindMap() ? player->FindMap()->GetMapName() : "Unknown",
            areaId, area ? area->area_name[locale] : "Unknown", zoneId, zone ? zone->area_name[locale] : "Unknown",
            selected ? selected->GetName() : "", player->GetTarget().ToString());
    }
}

class mod_ptr_changes_commandscript : public AllCommandScript
{
public:
    mod_ptr_changes_commandscript() : AllCommandScript("mod_ptr_changes_commandscript", { ALLCOMMANDHOOK_ON_TRY_EXECUTE_COMMAND }) { }

    bool OnTryExecuteCommand(ChatHandler& handler, std::string_view cmdStr) override
    {
        WorldSession* session = handler.GetSession();
        Player* player = session ? session->GetPlayer() : nullptr;
        if (!player)
            return true;

        std::string const line = ResolveCommandLine(handler, cmdStr);

        // Staff accounts are trusted; the PTR testing commands come from RBAC role 1000 on player accounts.
        std::string_view const refusal = AccountMgr::IsPlayerAccount(session->GetSecurity()) ? CheckGuardedCommand(handler, player, line) : std::string_view();

        LogCommand(session, player, cmdStr, line, refusal);

        if (refusal.empty())
            return true;

        handler.SendErrorMessage(refusal, false);
        return false;
    }
};

void Addmod_ptr_changesScript()
{
    new mod_ptr_changes_commandscript();
}
