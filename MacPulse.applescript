property appTitle : "MacPulse"

on run
	repeat
		set menuItems to {"Audit — battery & memory health report", "Deep Scan — kernel, GPU & thermal telemetry (admin)", "Tune — apply battery optimizations (admin)", "Guard — install adaptive daemon (admin)", "Unguard — remove daemon, restore defaults (admin)", "View Guard Log", "Quit"}
		set choice to choose from list menuItems with title appTitle with prompt "Adaptive battery + RAM governor for this Mac." default items {item 1 of menuItems}
		if choice is false then exit repeat
		set c to item 1 of choice
		try
			if c begins with "Audit" then
				doAudit()
			else if c begins with "Deep" then
				doDeep()
			else if c begins with "Tune" then
				doTune()
			else if c begins with "Guard" then
				doGuard()
			else if c begins with "Unguard" then
				doUnguard()
			else if c begins with "View" then
				doLog()
			else
				exit repeat
			end if
		on error errMsg number errNum
			if errNum is not -128 then display dialog "MacPulse: " & errMsg buttons {"OK"} default button 1 with icon caution with title appTitle
		end try
	end repeat
end run

on corePath()
	return POSIX path of (path to resource "macpulse-core.sh")
end corePath

on guardSrcPath()
	return POSIX path of (path to resource "guard-root.sh")
end guardSrcPath

on reportDir()
	set h to POSIX path of (path to home folder)
	do shell script "/bin/mkdir -p " & quoted form of (h & ".macpulse/reports")
	return h & ".macpulse/reports/"
end reportDir

on stamp()
	return do shell script "date +%Y%m%d-%H%M%S"
end stamp

on doAudit()
	set rpt to reportDir() & "audit-" & stamp() & ".txt"
	do shell script "/bin/zsh " & quoted form of corePath() & " audit > " & quoted form of rpt & " 2>&1"
	do shell script "open -e " & quoted form of rpt
end doAudit

on doDeep()
	display dialog "Deep Scan reads the kernel's own power model: per-core frequency and residency, CPU/GPU package power, SMC die temperatures and fan speed, the kernel's per-process energy-impact ranking, and kernel memory state. Takes about 15 seconds and needs your admin password." buttons {"Cancel", "Scan"} default button "Scan" with title appTitle
	set rpt to reportDir() & "deepscan-" & stamp() & ".txt"
	do shell script "/bin/zsh " & quoted form of corePath() & " deep " & quoted form of rpt with administrator privileges
	do shell script "open -e " & quoted form of rpt
end doDeep

on doTune()
	display dialog "Applies battery-side power settings (AC behaviour untouched):

- Power Nap off, wake-on-network off
- Display sleep 5 min, disk sleep 5 min
- Hibernate after 1 h asleep (15 min when under 50%)
- Integrated GPU only on battery — biggest single win on this dual-GPU Mac. Revert this one if you use an external display while unplugged.

Revert everything anytime: sudo pmset restoredefaults" buttons {"Cancel", "Apply"} default button "Apply" with title appTitle
	set out to do shell script "/bin/zsh " & quoted form of corePath() & " tune" with administrator privileges
	display dialog out buttons {"OK"} default button 1 with title appTitle
end doTune

on doGuard()
	display dialog "Installs a background daemon (runs as root every 60 s):

- On battery at 50% or below, or free memory at 25% or below: Low Power Mode ON
- Back on AC: Low Power Mode OFF
- Free memory at 12% or below: logs the top RAM hog

No sudoers/visudo changes needed — the daemon itself runs as root. Remove anytime with Unguard." buttons {"Cancel", "Install"} default button "Install" with title appTitle
	do shell script "/bin/zsh " & quoted form of corePath() & " guard-install " & quoted form of guardSrcPath() with administrator privileges
	display dialog "Guard installed and running. Check activity anytime with 'View Guard Log'." buttons {"OK"} default button 1 with title appTitle
end doGuard

on doUnguard()
	display dialog "Removes the Guard daemon, its log, and returns Low Power Mode to manual control." buttons {"Cancel", "Remove"} default button "Remove" with title appTitle
	do shell script "/bin/zsh " & quoted form of corePath() & " guard-remove" with administrator privileges
	display dialog "Guard removed." buttons {"OK"} default button 1 with title appTitle
end doUnguard

on doLog()
	set lg to "/Library/Application Support/MacPulse/macpulse.log"
	try
		do shell script "test -s " & quoted form of lg
		do shell script "open -e " & quoted form of lg
	on error
		display dialog "No guard activity logged yet. The first entry appears once Guard is installed and battery drops to 50% or below while unplugged." buttons {"OK"} default button 1 with title appTitle
	end try
end doLog
