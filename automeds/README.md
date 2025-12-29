**AutoMeds** is a Windower addon that tracks debuffs and automatically uses items to remove them.

## Features

**Buff Tracking List:**
	- Maintains a configurable list of monitored debuffs

**IPC Multi-Character Support:**
	- Broadcast debuff info to alts (trackalt)
	- Notify when Sneak/Invisible is wearing off (sitrack)

**Item Usage:**	
	- Automatically uses the correct item for common debuffs
	- Automatically skips item use if the item isn’t in your inventory
	- Retries item use until the debuff is cleared
	- Automatically stops once the debuff is gone

**Aura Awareness:**
	- Distance-based aura check will continuously scan nearby targets and their debuff within your aura list
	- Distance check only triggers if a matching target is within your set range **Default: 20 yalms**
	- Auto-suppress item usage if a debuff within in your aura list is detected nearby
	- Targets must be added to the aura list for Aura Awareness to work
	- Better than Smart Aura Block if you know what debuff you'll be encountering
	
**Smart Aura Block:**
	- Disabled by default
	- Works even if Aura Awareness is disabled
	- Pauses item use for a set duration if repeated attempts fail to remove a debuff **Default: 2 attempts then a 120 second pause**
	- Pause duration can be set between **60 - 600** seconds
	- Each debuff has it's own pause duration counter
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
- //ameds auraadd ["target"] [debuff] - Add target for Aura Awareness
- //ameds aurarem ["target"] [debuff] - Remove target from Aura Awareness
- //ameds auralist - List aura sources

## Notes

It's recommended to add targets directly to *sources_list* in defaults.global if you play multiple characters.
