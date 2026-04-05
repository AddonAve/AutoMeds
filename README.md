**AutoMeds** is a Windower addon that tracks debuffs and automatically uses items to remove them.

## Release Notes

**Version 1.8.0**
1. Uses a configurable priority list that handles one debuff at a time
2. 	- Send commands to other characters that are running the addon
		- Command: //ameds all [command]
3. Target lists will auto save in a separate file per character
4. Item attempts are only counted when the item actually fires successfully
5. Supports wildcard debuff matching which will block all debuffs of an added target
	- Command: //ameds auraadd "target" *
6. Pause duration is announced in chat log every 20 seconds
	- Edit: aura_reminder_interval in [settings]
		
## Features

**Buff Tracking**
	- Maintains a configurable list of monitored debuffs
	- Uses a configurable priority list that handles one debuff at a time
	
**IPC Multi-Character Support**
	- Broadcast debuff info to alts (trackalt)
	- Notify when Sneak/Invisible is wearing off (sitrack)
	- Send commands to other characters that are running the addon
		- Command: //ameds all [command]
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

Do not type [ ] or < > when using commands:

List commands: //ameds help

- //ameds trackalt - Toggle broadcast for debuffs on your alts
- //ameds all [command] - Send a command below to all characters
- //ameds toggle - Toggle on/off
- //ameds watch [buff] - Track a debuff
- //ameds unwatch [buff] - Untrack a debuff
- //ameds list - Show tracked debuffs
- //ameds sitrack - Toggle Sneak/Invisible wear tracker
- //ameds aura [on|off] - Enable/Disable Aura Awareness
- //ameds aurasmart [on|off] - Enable/Disable Smart Aura Block
- //ameds aurablock <seconds> - Set pause duration <60 - 600>
- //ameds auradistance <yalms> - Set distance detection for Aura Awareness <1 - 20>
- //ameds auraadd "target" [debuff|*] - Add target and debuff for Aura Awareness
- //ameds auraremove "target" [debuff|*] - Remove target and debuff from Aura Awareness
- //ameds auralist - List all aura sources
- //ameds auralist "target" - List aura sources for target
