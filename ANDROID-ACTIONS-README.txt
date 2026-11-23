ASHFALL - gerar APK pelo GitHub Actions

Este pacote inclui:
- .github/workflows/android-apk.yml
- export_presets.cfg (predefinicao Android APK que faltava no ZIP enviado)

Como usar:
1. Extraia o ZIP do projeto.
2. Envie TODO o conteudo da pasta ashfall-main para um repositorio GitHub.
3. No GitHub, abra a aba Actions.
4. Se necessario, habilite Actions para o repositorio.
5. Selecione "Build ASHFALL Android APK" e clique em Run workflow.
6. Aguarde a execucao terminar com sucesso.
7. Abra a execucao concluida e baixe o artefato "ASHFALL-Android-APK".
8. Extraia o ZIP do artefato e instale ashfall.apk no Android.

O workflow gera um APK de depuracao, assinado com a chave de depuracao automatica.
Ele serve para instalar e testar no aparelho; nao e uma compilacao assinada para publicar
na Google Play. O pacote Android foi configurado como com.ashfall.game.

Observacao: o projeto informa que ainda nao foi validado em aparelho fisico. A compilacao
pode revelar problemas de compatibilidade ou de configuracao que exigirao ajustes.
