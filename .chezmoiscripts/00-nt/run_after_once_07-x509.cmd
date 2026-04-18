@echo off
REM installing certificate
echo debug: installing custom certificate
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\ipa-ca.crt"
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\pve-root-ca.pem"
