# Hola-AI for Windows (Scaffold)

This folder contains a Windows desktop scaffold for Hola-AI.

## Stack

- C# 12
- .NET 8 (`net8.0-windows`)
- WPF (desktop UI)

## Current status

- Overlay window scaffolded (draggable, always-on-top style)
- Model/config structures scaffolded
- Service layer scaffolded for:
- Global hotkeys
- Audio capture
- OpenRouter API calls
- Text insertion into active app

This is an MVP starter and needs feature completion + hardening before production.

## Build on Windows

1. Install .NET 8 SDK.
2. Open PowerShell in this folder.
3. Run:

```powershell
dotnet restore .\src\HolaAI.Windows\HolaAI.Windows.csproj
dotnet build .\src\HolaAI.Windows\HolaAI.Windows.csproj -c Release
dotnet run --project .\src\HolaAI.Windows\HolaAI.Windows.csproj
```

## Next implementation steps

1. Complete `AudioCaptureService` with robust start/stop + level metering.
2. Wire `OpenRouterClient.TranscribeAndCleanAsync` into the record flow.
3. Implement accessibility-safe insertion fallback strategy in `TextInsertionService`.
4. Add installer/signing pipeline (MSIX/Inno Setup + code signing).
