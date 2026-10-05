# FOS v1

## Run FOS

Right-click `FOS.ps1` and run with PowerShell, or use:

powershell -ExecutionPolicy Bypass -File .\FOS.ps1

## Run the local server

powershell -ExecutionPolicy Bypass -File .\Server\server.ps1

## Upload limit

10 bytes minimum.
100 MB maximum.

## Philosophy

FOS is an open-source command-driven platform.

Third-party plugins are not automatically trusted.
Do not install plugins from people you do not trust.

The local server is intended for development.
A production internet server should validate every request
and never trust the client with permissions.
