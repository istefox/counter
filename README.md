# counter
## Rilascio

1. Aggiorna `CFBundleShortVersionString` (e `CFBundleVersion`) in `Project.swift` e fai merge su `main`.
2. Crea e pusha il tag corrispondente: `git tag v0.2.0 && git push origin v0.2.0`.
3. Il workflow `Release` compila l'app su macOS e pubblica la release con `AgentLimits-vX.Y.Z.zip`.

L'app nello zip è firmata ad hoc (non Developer ID). Al primo avvio: `xattr -dr com.apple.quarantine /Applications/AgentLimits.app`.
