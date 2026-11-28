# Seal Tracker

A small seal tracker for Paladins on World of Warcraft Forever, built around **Unsealed Wrath** for Retribution. It works on every spec: without the talent you get the seal icon and timer, with no Echo stacks.

WoW Forever hides seal and Echo buffs from addons in combat. Instead of guessing, Seal Tracker lets the game draw everything itself (Blizzard's AuraContainer display), so the seal timer, Echo stacks and swap glow stay correct in combat.

## What you see

- **One round icon** for the seal that's up, with the seconds left in the middle.
- **3 dots below the icon**: your current seal's Echo stacks. A coloured ring glows around the icon at 3 stacks, which means swap.
- **Small dots above the icon**: Echo stacks left over from the seal you swapped off, until they're used up.
- **No seal**: a greyed-out icon with a red "!", or nothing at all with "Hide when no seal is up".

Tracked seals: Command, Righteousness, Wisdom, Fury, Justice, Light and the Crusader. Echo IDs for Command, Righteousness and Wisdom are built in. Others are found by spell name at login, or learned the first time the Echo is on you out of combat.

## Options

Open them with the minimap button, the addon list button by the minimap, or `/st`.

- Lock position (drag the icon to move it while unlocked)
- Show leftover Echo dots above the icon
- Hide when no seal is up (once locked)
- Show minimap button
- Size, reset position, print status

Commands: `/st` (options), `/st status`, `/st reset`, `/st minimap`.

## Install

Copy the files into a folder named `SealTracker` in your Forever client's `Interface\AddOns` folder:

```
World of Warcraft\_forever_\Interface\AddOns\SealTracker\
```

## Credits

- Seal spell ID data: [talentsforever.com](https://talentsforever.com) (CC BY 4.0).
- Inspired by [Unsealed Wrath Tracker](https://www.curseforge.com/wow/addons/unsealed-wrath-tracker), which showed that Blizzard's aura display can be used to stay accurate in combat.
