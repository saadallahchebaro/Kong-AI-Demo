-- GNB demo: double-click to open the Run tab (the demo's shortcuts) in your browser, starting its server if needed.
-- Built into "GNB demo.app" in the main folder by 3-cli-ui-webui/launcher/build.sh. The app finds the repo from where it sits.
set appPath to POSIX path of (path to me)
set repo to do shell script "dirname " & quoted form of appPath
try
	-- a login shell, so node, docker and kongctl are on the PATH as in Terminal
	do shell script "/bin/zsh -lc " & quoted form of ("cd " & quoted form of repo & " && 3-cli-ui-webui/scripts/panes.sh --run")
on error errText
	display dialog "GNB demo couldn't start the Run tab:" & return & return & errText buttons {"OK"} default button 1 with icon caution
end try
