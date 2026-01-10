@echo off
"%USERPROFILE%\scoop\apps\clink\current\clink.bat" inject --autorun && doskey /macrofile="%USERPROFILE%\.doskey.mac"
