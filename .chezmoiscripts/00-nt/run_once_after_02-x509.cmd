@echo off
REM installing certificate
echo debug: installing custom certificate(s)
REM home.arpa
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\ipa-ca.crt"
REM regulad.internal
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\regulad.internal.crt"
REM cohensstore003.internal
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\cohensstore003.internal.crt"
REM gonkputer nonspecific
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\pve-root-ca.pem"
