# counter
## Rilascio

1. Aggiorna `CFBundleShortVersionString` (e `CFBundleVersion`) in `Project.swift` e fai merge su `main`.
2. Avvia il workflow `Release` da Actions (Run workflow su `main`), oppure pusha il tag: `git tag v0.2.0 && git push origin v0.2.0`.
3. Il workflow crea il tag se manca, compila l'app su macOS e pubblica la release con `AgentLimits-vX.Y.Z.zip`.

L'app nello zip è firmata ad hoc (non Developer ID). Al primo avvio: `xattr -dr com.apple.quarantine /Applications/AgentLimits.app`.
