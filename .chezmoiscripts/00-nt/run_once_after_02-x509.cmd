@echo off
REM installing certificate
echo debug: installing custom certificate(s)
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\ipa-ca.crt"
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\pve-root-ca.pem"

sudo certutil -addstore "Root" "%USERPROFILE%\.x509\GUI+default+(66c76753e5636).crt"
sudo certutil -addstore "Root" "%USERPROFILE%\.x509\GUI+default+(6a6907bb2c8b7).crt"
