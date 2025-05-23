#!/bin/bash 

# -----------------------------------------------------------------------------
# SCRIPT DE EXCLUSÃO DE ARTEFATOS NO HARBOR
# -----------------------------------------------------------------------------
# Descrição:
# Este script é utilizado para listar repositórios e artefatos em projetos do 
# Harbor, e deletar artefatos antigos, mantendo apenas os 
# mais recentes (ou um número configurável de artefatos) em cada repositório.
# Ele utiliza a API do Harbor para buscar os dados e relizar a exclusão
#
# Arquivo de configuração (config.env)
# O arquivo `config.env` deve conter as variáveis de ambiente necessárias 
# para a execução do script: usuário, senha, URL do Harbor, e os nomes
# dos projetos a serem processados.
#


# Carregar variáveis do arquivo config.env
source /root/clean_artifacts/config.env

echo "#################################################################################################" 
echo "Script executado em: $(date +'%d/%m/%Y %H:%M:%S')" 

# Função para listar repositórios e gerenciar artefatos
manage_artifacts() {
    local PROJECT_NAME="$1"
    local PAGE=1
    local PAGE_SIZE=10

    echo "Listando repositórios no projeto: $PROJECT_NAME"

    # Continuar buscando enquanto houver repositórios
    while true; do
        # Requisição para buscar repositórios com paginação
        REPOSITORIES=$(curl -s -k -u "$USERNAME:$PASSWORD" "$HARBOR_URL/projects/$PROJECT_NAME/repositories?page=$PAGE&page_size=$PAGE_SIZE")

        # Verifica se a resposta contém repositórios
        if [ $(echo "$REPOSITORIES" | jq 'length') -eq 0 ]; then
            echo "Nenhum repositório adicional encontrado no projeto $PROJECT_NAME na página $PAGE."
            break
        fi

        # Itera sobre cada repositório na página atual
        for REPO in $(echo "$REPOSITORIES" | jq -r '.[].name'); do
            REPO_NAME=$(echo "$REPO" | sed "s|^$PROJECT_NAME/||")

            echo "Listando artefatos no repositório: $REPO_NAME"
            ARTIFACTS_RESPONSE=$(curl -s -k -u "$USERNAME:$PASSWORD" "$HARBOR_URL/projects/$PROJECT_NAME/repositories/$REPO_NAME/artifacts?page_size=100")

            # Verifica se houve um erro na resposta
            if echo "$ARTIFACTS_RESPONSE" | jq -e '.errors?' >/dev/null; then
                echo "Erro ao buscar artefatos: $(echo "$ARTIFACTS_RESPONSE" | jq -r '.errors[0].message')"
                continue
            fi

            # Extrai as tags dos artefatos e suas datas de push
            ARTIFACTS=$(echo "$ARTIFACTS_RESPONSE" | jq -r '.[] | select(.tags != null) | {name: .tags[0].name, pushed_at: .pushed_at}')

            if [ -z "$ARTIFACTS" ]; then
                echo "Nenhum artefato com tag encontrado no repositório $REPO_NAME."
                continue
            fi

            echo "Artefatos em $REPO_NAME:"
            echo "$ARTIFACTS" | jq -r '.name'

            # Ordena os artefatos pela data de push e seleciona os dois mais recentes
            # em caso de data igual é ordenado pela versão.
            RECENT_ARTIFACTS=$(echo "$ARTIFACTS" | jq -s 'sort_by(.pushed_at, .name) | reverse | .[0:2]')
            #RECENT_ARTIFACTS=$(echo "$ARTIFACTS" | jq -s 'sort_by(.pushed_at) | reverse | .[0:2]')
            if [ -z "$RECENT_ARTIFACTS" ]; then
                echo "Não foi possível identificar os artefatos mais recentes."
                continue
            fi

            echo "Mantendo os artefatos mais recentes:"
            echo "$RECENT_ARTIFACTS" | jq -r '.[].name'

            # Deletar artefatos que não estão entre os dois mais recentes
            echo "$ARTIFACTS" | jq -r '.name' | while read -r ARTIFACT_NAME; do
                if ! echo "$RECENT_ARTIFACTS" | jq -e --arg ARTIFACT_NAME "$ARTIFACT_NAME" 'any(.name == $ARTIFACT_NAME)' >/dev/null; then
                    echo "Deletando artefato: $ARTIFACT_NAME do repositório $REPO_NAME"
                    curl -s -k -u "$USERNAME:$PASSWORD" -X DELETE "$HARBOR_URL/projects/$PROJECT_NAME/repositories/$REPO_NAME/artifacts/$ARTIFACT_NAME"
                fi
            done
           
            echo "Dois artefatos mais recentes em $REPO_NAME:"
            echo "$RECENT_ARTIFACTS" | jq -r '.[].name'
        done

        # Incrementa a página para a próxima requisição
        PAGE=$((PAGE + 1))
    done
}

# Verifica cada projeto
for PROJECT in "${PROJECTS[@]}"; do
    manage_artifacts "$PROJECT"
done
