# Enchantment Effect Retention Specification

## Target

- Minecraft: `1.21.1`
- Yarn mappings: `1.21.1+build.3`
- Fabric Loader: `0.19.2` or later, as declared by `fabric.mod.json`
- Fabric API: `0.116.11+1.21.1`
- Scope: client-side item A/B switching investigation only. This document does not define an implementation, UI, or automatic loop.

## Source-Based Finding

Minecraft 1.21.1 defines vanilla enchantment behavior in `data/minecraft/enchantment/*.json`. For hand-held item switching, only enchantments whose effect is an attribute modifier in the active hand slot can plausibly remain after item A is no longer selected. Event-style enchantments are evaluated from the item stack used by the current action and should be treated as not retained after switching.

The retained window is at most one server equipment-update tick. When the selected slot changes, the server receives the new selected slot immediately, but the entity attribute set that came from the previous hand item is refreshed during the next living-entity equipment update. At 20 TPS this is normally 0 to 1 game tick, or 0 to 50 ms. On a lagging server the wall-clock duration stretches with tick time, but the authoritative duration is still one server tick. If the switch is processed before the equipment update for that tick, the retained window can be 0 ticks.

## Item A/B Conditions

- Item A must be selected in the main hand before the switch and must carry a hand-slot attribute enchantment.
- Item B must be selected immediately after item A and must be the item used for the next player action.
- The effect that appears to remain is the attribute modifier already present on the player, not item A's full enchantment state.
- Item B does not inherit item A's loot, damage, projectile, ammo, or post-attack enchantment effects.
- Armor-slot enchantments follow the same equipment-update principle, but armor swapping is outside this A/B hotbar-switching scope.

## Vanilla Enchantment Categories

Hand-slot attribute effects that can be retained for the short equipment-update window:

- `minecraft:efficiency`: `minecraft:player.mining_efficiency`, slot `mainhand`
- `minecraft:sweeping_edge`: `minecraft:player.sweeping_damage_ratio`, slot `mainhand`

Armor or non-hotbar attribute effects, not part of hand A/B switching:

- `minecraft:aqua_affinity`, `minecraft:respiration`, `minecraft:depth_strider`, `minecraft:swift_sneak`
- `minecraft:blast_protection`, `minecraft:fire_protection`
- `minecraft:soul_speed` includes location/tick effects in addition to temporary attribute application

Effects that should not be considered retained by item A/B hand switching:

- Direct damage and knockback: `sharpness`, `smite`, `bane_of_arthropods`, `impaling`, `power`, `punch`, `knockback`
- Post-attack or projectile effects: `fire_aspect`, `flame`, `channeling`, `wind_burst`
- Loot, drop, and block-result effects: `fortune`, `silk_touch`, `looting`, `luck_of_the_sea`, `lure`
- Ammo, durability, trident, and crossbow effects: `infinity`, `mending`, `unbreaking`, `loyalty`, `riptide`, `multishot`, `piercing`, `quick_charge`

## Reproduction Procedure

1. Start a single-player world on Minecraft `1.21.1` with Fabric Loader `0.19.2+` and Fabric API `0.116.11+1.21.1`.
2. Put item A in a hotbar slot and item B in another hotbar slot.
3. Use an Efficiency-enchanted mining tool as item A. Use a different item B that can perform the action being measured.
4. Select item A for at least one full tick so its main-hand attribute modifier is applied.
5. Switch to item B and trigger the measured action in the same client tick or as close as possible to the slot-change packet.
6. Compare action behavior at tick offsets 0, 1, and 2 after switching.

Expected result:

- At offset 0, item A's attribute effect may still influence the player.
- By offset 1 server tick after the equipment update, the attribute effect should be gone unless item B supplies its own matching effect.
- At offset 2, item A's effect should be absent.

Negative checks:

- Fortune or Silk Touch on item A should not affect item B's block drops after switching.
- Sharpness, Knockback, Fire Aspect, Power, Punch, or Flame on item A should not affect item B's attack or projectile after switching.

## Effect End Conditions

The retained effect ends when any of the following occurs:

- The next server-side living-entity equipment update removes item A's attribute modifiers.
- Item B is replaced by another selected item before the measured action.
- The player dies, changes world/dimension, disconnects, or the inventory state is resynchronized.
- A server plugin/mod performs its own inventory, attribute, or anti-cheat correction.

## Implementation Timing Candidates

These are reference points for later implementation, not implemented in this sub-issue:

- `ClientTickEvents.END_CLIENT_TICK`: poll key/use state and schedule A/B slot changes after normal client input.
- `UpdateSelectedSlotC2SPacket`: packet used to notify the server of the selected hotbar slot.
- `AttackBlockCallback`, `UseBlockCallback`, `UseItemCallback`, `AttackEntityCallback`: candidate Fabric interaction events for measuring whether the action happens in the retained window.
- `LivingEntity` equipment-change processing and `onEquipStack`: server-side point where old item attribute modifiers are removed and new ones are applied.
- `EnchantmentHelper`: source of current-action enchantment evaluation; effects queried from the current item stack should not be modeled as retained.

## Multiplayer Risk

This behavior is timing-dependent and server-authoritative. Multiplayer servers can change the practical window through TPS, latency, plugin behavior, or anti-cheat inventory checks. Any later implementation must default to conservative timing, fail closed when slot state is uncertain, and warn users to follow server rules.
