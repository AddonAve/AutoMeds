**AutoMeds** is a Windower addon that tracks debuffs and automatically uses items to remove them.

## Release Notes

**Version 1.8.0**
- Uses a configurable priority list that handles one debuff at a time
- Control target lists on every character with one command
	- Command: //ameds all auraadd "target" [debuff|*]
	- Command: //ameds all auraremove "target" [debuff|*]
- Target lists will auto save in a separate file per character
- Item attempts are only counted when the item actually fires successfully
- Supports wildcard debuff matching which will block all debuffs of an added target
	- Command: //ameds auraadd "target" *
- Pause duration is announced in chat log every 20 seconds
	- Edit: aura_reminder_interval in [settings]
		
## Features

**Buff Tracking**
	- Maintains a configurable list of monitored debuffs
	- Uses a configurable priority list that handles one debuff at a time
	
**IPC Multi-Character Support**
	- Broadcast debuff info to alts (trackalt)
	- Notify when Sneak/Invisible is wearing off (sitrack)
	- Control target lists on every character with one command
		- Command: //ameds all auraadd "target" [debuff|*]
		- Command: //ameds all auraremove "target" [debuff|*]
	- Target lists will auto save in a separate file per character
		
**Item Usage**	
	- Automatically uses the correct item for common debuffs
	- Automatically skips item use if the item isn’t in your inventory
	- Retries item use until the debuff is cleared
	- Automatically stops once the debuff is gone
	- Item attempts are only counted when the item actually fires successfully

**Aura Awareness**
	- Distance-based aura check will continuously scan nearby targets and their debuff within your aura list
	- Distance check only triggers if a matching target is within 20 yalms
		- Edit: distance in [settings]
	- Auto-suppress item usage if a debuff within in your aura list is detected nearby
	- Targets must be added in order for Aura Awareness to work
		- Command: //ameds auraadd "target" debuff
	- Supports wildcard debuff matching which will block all debuffs of an added target
		- Command: //ameds auraadd "target" *
	
**Smart Aura Block**
	- If you disable Smart Aura Block, Aura Awarness will still function
	- Pauses item use for 120 seconds after 2 attempts fail to remove a debuff
		- Edit: max_attempts, block_time in [settings]
	- Pause duration can be set between 60 - 600 seconds
		- Edit: block_time in [settings]
	- Each debuff configured in **Buff Tracking** receives it's own pause duration
	- Pause duration is announced in chat log every 20 seconds
		- Edit: aura_reminder_interval in [settings]
	- Pause duration resets when the debuff is no longer active

## Commands

Do not type [ ] when using commands:

List commands: //ameds help

- //ameds toggle - Toggle Automeds On/Off
- //ameds watch [buff] - Track a debuff
- //ameds unwatch [buff] - Untrack a debuff
- //ameds list - Show tracked debuffs
- //ameds trackalt - Toggle alt broadcast
- //ameds sitrack - Toggle Sneak/Invisible wear tracker
- //ameds aura on|off - Enable/Disable Aura Awareness
- //ameds aurasmart on|off - Enable/Disable Smart Aura Block
- //ameds aurablock [seconds] - Set pause duration [60 - 600]
- //ameds auradistance [yalms] - Set distance detection for Aura Awareness
- //ameds auraadd [all] "target" [debuff|*] - Add target and debuff for Aura Awareness
- //ameds auraremove [all] "target" [debuff|*] - Remove target and debuff from Aura Awareness
- //ameds auralist - List aura sources
