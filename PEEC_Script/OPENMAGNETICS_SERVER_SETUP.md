# OpenMagnetics Local Server Setup (Windows)

## Overview
This guide explains how to run the local OpenMagnetics server used by the tool.

## Requirements
- Windows 10 or 11
- Python 3.11.x 64-bit (recommended)
- Internet access for first-time pip install

## Download Python 3.11
Use the official Python downloads page and choose Python 3.11.x (64-bit).
```
https://www.python.org/downloads/
```

## Install Dependencies
Run the commands in PowerShell. If `python` on PATH is not 3.11, use the full path to Python 3.11.

### Recommended: install in a virtual environment
```
C:\Users\Will\AppData\Local\Programs\Python\Python311\python.exe -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install PyOpenMagnetics flask
```

### Direct install (system Python 3.11)
```
C:\Users\Will\AppData\Local\Programs\Python\Python311\python.exe -m pip install PyOpenMagnetics flask
```

### Quick checks
```
python --version
python -m pip --version
```
The version must be `3.11.x` for the server dependencies to build reliably.

## Run the Server
Keep this window open while using the GUI.
```
C:\Users\Will\AppData\Local\Programs\Python\Python311\python.exe C:\Users\Will\Downloads\om_server.py --port 8484
```

## Verify the Server
In a new PowerShell window:
```
Invoke-RestMethod http://localhost:8484/health
```
Expected output includes `status: ok` and `pyom_available: true`.

## Use in the GUI
- Start the server first.
- Open the GUI and set Data Mode to Online.
- Server URL should be `http://localhost:8484`.

## Troubleshooting
- If `python --version` shows 3.14, call Python 3.11 by its full path or adjust PATH.
- If pip install fails with long file name errors, enable Windows long paths or set `TEMP` and `TMP` to a short path and retry.
- If the GUI says the health check failed, confirm `/health` returns JSON in the browser or PowerShell.
- If PowerShell `curl` returns Access is denied, use `curl.exe` or `Invoke-RestMethod`.
- The server must stay running while the GUI is in Online mode.
