#!/bin/bash

# Activa el entorno virtual principal
source /venv/main/bin/activate
A1111_DIR=${WORKSPACE}/stable-diffusion-webui

# Paquetes a instalar usando apt (sistema)
APT_PACKAGES=(
    #"package-1"
    #"package-2"
)

# Paquetes a instalar usando pip (Python)
PIP_PACKAGES=(
    # Ejemplo: "xformers"
)

# Extensiones de Stable Diffusion a clonar
EXTENSIONS=(
    "https://github.com/gutris1/sd-hub.git"
    "https://github.com/Mikubill/sd-webui-controlnet.git"
    "https://github.com/hako-mikan/sd-webui-regional-prompter.git"
    "https://github.com/Bing-su/adetailer.git"
)

# Modelos Checkpoint (Base models)
CHECKPOINT_MODELS=(
    "https://civitai.com/api/download/models/798204?type=Model&format=SafeTensor&size=full&fp=fp16"
    # Puedes añadir más modelos aquí:
    # "https://civitai.com/api/download/models/XXXXX"
)

# Modelos UNET (Opcional, para modelos más grandes)
UNET_MODELS=(
)

# Modelos LoRA
LORA_MODELS=(
)

# Modelos VAE
VAE_MODELS=(
)

# Modelos ESRGAN (Upscalers)
ESRGAN_MODELS=(
)

# Modelos ControlNet (se descargan en un paso separado)
CONTROLNET_MODELS=(
    # Ejemplo: "https://huggingface.co/lllyasviel/ControlNet-v1-1/resolve/main/control_v11p_sd15_canny.pth"
)

### DO NOT EDIT BELOW HERE UNLESS YOU KNOW WHAT YOU ARE DOING ###

function provisioning_start() {
    provisioning_print_header
    provisioning_get_apt_packages
    # Llama a la nueva función para descargar las extensiones
    provisioning_get_extensions 
    provisioning_get_pip_packages

    # Descarga los modelos Checkpoint
    provisioning_get_files \
        "${A1111_DIR}/models/Stable-diffusion" \
        "${CHECKPOINT_MODELS[@]}"

    # Descarga modelos para el ControlNet (si se especificaron)
    provisioning_get_files \
        "${A1111_DIR}/extensions/sd-webui-controlnet/models" \
        "${CONTROLNET_MODELS[@]}"
    
    # Evita errores de git porque se ejecuta como root pero los archivos son de 'user'
    export GIT_CONFIG_GLOBAL=/tmp/temporary-git-config
    git config --file $GIT_CONFIG_GLOBAL --add safe.directory '*'

    # Inicia y sale porque webui probablemente requerirá un reinicio después del provisionamiento
    cd "${A1111_DIR}"
    LD_PRELOAD=libtcmalloc_minimal.so.4 \
        python launch.py \
            --skip-python-version-check \
            --no-download-sd-model \
            --do-not-download-clip \
            --no-half \
            --port 11404 \
            --exit

    provisioning_print_end
}

function provisioning_get_apt_packages() {
    if [[ -n $APT_PACKAGES ]]; then
            sudo $APT_INSTALL ${APT_PACKAGES[@]}
    fi
}

function provisioning_get_pip_packages() {
    if [[ -n $PIP_PACKAGES ]]; then
            pip install --no-cache-dir ${PIP_PACKAGES[@]}
    fi
}

function provisioning_get_extensions() {
    for repo in "${EXTENSIONS[@]}"; do
        dir="${repo##*/}"
        # Elimina el sufijo .git para obtener el nombre de la carpeta
        dir="${dir%.git}" 
        path="${A1111_DIR}/extensions/${dir}"
        if [[ ! -d $path ]]; then
            printf "Downloading extension: %s...\n" "${repo}"
            git clone "${repo}" "${path}" --recursive
        else
            printf "Extension already exists: %s\n" "${dir}"
        fi
    done
}

# La función provisioning_get_files es la encargada de descargar los modelos.
function provisioning_get_files() {
    if [[ -z $2 ]]; then return 1; fi
    
    dir="$1"
    mkdir -p "$dir"
    shift
    arr=("$@")
    printf "Downloading %s model(s) to %s...\n" "${#arr[@]}" "$dir"
    for url in "${arr[@]}"; do
        printf "Downloading: %s\n" "${url}"
        provisioning_download "${url}" "${dir}"
        printf "\n"
    done
}

function provisioning_print_header() {
    printf "\n##############################################\n#                                            #\n#          Provisioning container            #\n#                                            #\n#         This will take some time           #\n#                                            #\n# Your container will be ready on completion #\n#                                            #\n##############################################\n\n"
}

function provisioning_print_end() {
    printf "\nProvisioning complete:  Application will start now\n\n"
}

function provisioning_has_valid_hf_token() {
    [[ -n "$HF_TOKEN" ]] || return 1
    url="https://huggingface.co/api/whoami-v2"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $HF_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

function provisioning_has_valid_civitai_token() {
    [[ -n "$CIVITAI_TOKEN" ]] || return 1
    url="https://civitai.com/api/v1/models?hidden=1&limit=1"

    response=$(curl -o /dev/null -s -w "%{http_code}" -X GET "$url" \
        -H "Authorization: Bearer $CIVITAI_TOKEN" \
        -H "Content-Type: application/json")

    # Check if the token is valid
    if [ "$response" -eq 200 ]; then
        return 0
    else
        return 1
    fi
}

# Download from $1 URL to $2 file path
function provisioning_download() {
    if [[ -n $HF_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?huggingface\.co(/|$|\?) ]]; then
        auth_token="$HF_TOKEN"
    elif 
        [[ -n $CIVITAI_TOKEN && $1 =~ ^https://([a-zA-Z0-9_-]+\.)?civitai\.com(/|$|\?) ]]; then
        auth_token="$CIVITAI_TOKEN"
    fi
    if [[ -n $auth_token ]];then
        wget --header="Authorization: Bearer $auth_token" -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    else
        wget -qnc --content-disposition --show-progress -e dotbytes="${3:-4M}" -P "$2" "$1"
    fi
}

# Permite al usuario deshabilitar el provisionamiento si no lo desea
if [[ ! -f /.noprovisioning ]]; then
    provisioning_start
fi