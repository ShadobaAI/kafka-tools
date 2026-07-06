FROM sonarqube:community

# Версии плагинов меняются только здесь.
ARG BSL_PLUGIN_VERSION=1.18.1
ARG L10N_RU_PLUGIN_VERSION=25.7
ARG SONARQUBE_PLUGINS_DIR=/opt/sonarqube/extensions/plugins

# Плагины должны лежать в каталоге extensions/plugins перед стартом SonarQube.
ADD --chown=sonarqube:root \
    https://github.com/1c-syntax/sonar-bsl-plugin-community/releases/download/v${BSL_PLUGIN_VERSION}/sonar-communitybsl-plugin-${BSL_PLUGIN_VERSION}.jar \
    ${SONARQUBE_PLUGINS_DIR}/

ADD --chown=sonarqube:root \
    https://github.com/1c-syntax/sonar-l10n-ru/releases/download/v${L10N_RU_PLUGIN_VERSION}/sonar-l10n-ru-plugin-${L10N_RU_PLUGIN_VERSION}.jar \
    ${SONARQUBE_PLUGINS_DIR}/
