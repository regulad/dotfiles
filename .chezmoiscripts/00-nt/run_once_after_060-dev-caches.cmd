@echo off

if not exist D:\packages        mkdir D:\packages
if not exist D:\packages\npm    mkdir D:\packages\npm
if not exist D:\packages\nuget  mkdir D:\packages\nuget
if not exist D:\packages\vcpkg  mkdir D:\packages\vcpkg
if not exist D:\packages\pip    mkdir D:\packages\pip
if not exist D:\packages\cargo  mkdir D:\packages\cargo
if not exist D:\packages\maven  mkdir D:\packages\maven
if not exist D:\packages\gradle mkdir D:\packages\gradle

if exist "%AppData%\npm-cache"           robocopy "%AppData%\npm-cache"           D:\packages\npm    /E /MOVE
if exist "%USERPROFILE%\.nuget\packages" robocopy "%USERPROFILE%\.nuget\packages" D:\packages\nuget  /E /MOVE
if exist "%LOCALAPPDATA%\vcpkg\archives" robocopy "%LOCALAPPDATA%\vcpkg\archives" D:\packages\vcpkg  /E /MOVE
if exist "%LocalAppData%\pip\Cache"      robocopy "%LocalAppData%\pip\Cache"      D:\packages\pip    /E /MOVE
if exist "%USERPROFILE%\.cargo"          robocopy "%USERPROFILE%\.cargo"          D:\packages\cargo  /E /MOVE
if exist "%USERPROFILE%\.m2\repository"  robocopy "%USERPROFILE%\.m2\repository"  D:\packages\maven  /E /MOVE
if exist "%USERPROFILE%\.gradle"         robocopy "%USERPROFILE%\.gradle"         D:\packages\gradle /E /MOVE

sudo setx /M npm_config_cache           D:\packages\npm
sudo setx /M NUGET_PACKAGES             D:\packages\nuget
sudo setx /M VCPKG_DEFAULT_BINARY_CACHE D:\packages\vcpkg
sudo setx /M PIP_CACHE_DIR              D:\packages\pip
sudo setx /M CARGO_HOME                 D:\packages\cargo
sudo setx /M MAVEN_OPTS                 "-Dmaven.repo.local=D:\packages\maven"
sudo setx /M GRADLE_USER_HOME           D:\packages\gradle
