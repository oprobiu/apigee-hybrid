#!/bin/bash
# Checks for the dependecies listed in the README
LIST_COMMANDS=('helm' 'kubectl' 'gcloud' 'jq' 'bash' 'whiptail')
MIN_HELM_VERSION='3.10.0'
MIN_KUBECTL_VERSION='1.10.0'
MIN_GCLOUD_VERSION='498.0.0'
MIN_JQ_VERSION='1.7'
MIN_BASH_VERSION='5.0'
MIN_WHIPTAIL_VERSION='0.52'
isCommand(){
    # checks if the list of commands is installed
    for comm in "${@}"; do
        echo "[${FUNCNAME[*]}] Verifying that the command '$comm' exists..." >&2 
        command -v "$comm" > /dev/null
        if [[ "$?" != "0" ]]; then echo "[ERROR][${FUNCNAME[*]}] '$comm' is missing. Verify that all of the commands '${*}' are available. Exiting..."; return 1;
        else echo "[${FUNCNAME[*]}] '$comm' is present." >&2
        fi
    done
    return 0
}

isGE(){
    # checks if number $1 is >= than $2
    if (( "$1" >= "$2" )); then return 0;
    else return 1; fi 
}

isGEString() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" == "$2" ]
}


helmCheck(){
    local currentHelm=
    currentHelm=$(helm version --short | sed -n 's/^v\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
    if [[ "$?" != "0" ]]; then echo "[${FUNCNAME[*]}] helm version check failed.">&2; return 1; fi
    if isGEString "$currentHelm" "$MIN_HELM_VERSION"; then 
        echo "[${FUNCNAME[*]}] helm version condition met." >&2
        return 0
    else
        echo "[${FUNCNAME[*]}] helm version condition not met. 
        Min.    Helm version: ${MIN_HELM_VERSION}
        Current Helm version: ${currentHelm}"  >&2
        return 1
    fi
}

kubectlCheck(){
    local currentKubectl=
    currentKubectl=$(kubectl version --client | grep 'Client Version' | awk '{print $3}' | sed 's/^v//; s/-.*//')
    if [[ "$?" != "0" ]]; then echo "[${FUNCNAME[*]}] kubectl version check failed.">&2; return 1; fi
    if isGEString "$currentKubectl" "$MIN_KUBECTL_VERSION"; then 
        echo "[${FUNCNAME[*]}] kubectl version condition met." >&2
        return 0
    else
        echo "[${FUNCNAME[*]}] kubectl version condition not met. 
        Min.    kubectl version: ${MIN_KUBECTL_VERSION}
        Current kubectl version: ${currentKubectl}"  >&2
        return 1
    fi
}


gcloudCheck(){
    local currentGCLOUD=
    currentGCLOUD=$(gcloud version | grep 'Google Cloud SDK' | awk '{print $4}')
    if [[ "$?" != "0" ]]; then echo "[${FUNCNAME[*]}] gcloud version check failed.">&2; return 1; fi
    if isGEString "$currentGCLOUD" "$MIN_GCLOUD_VERSION"; then 
        echo "[${FUNCNAME[*]}] gcloud version condition met." >&2
        return 0
    else
        echo "[${FUNCNAME[*]}] gcloud version condition not met. 
        Min.    gcloud version: ${MIN_GCLOUD_VERSION}
        Current gcloud version: ${currentGCLOUD}"  >&2
        return 1
    fi   
}

jqCheck(){
    local currentJQ=
    currentJQ=$(jq --version | sed 's/jq-//')
    if isGEString "$currentJQ" "$MIN_JQ_VERSION"; then 
        echo "[${FUNCNAME[*]}] jq version condition met." >&2
        return 0
    else
        echo "[${FUNCNAME[*]}] jq version condition not met. 
        Min.    jq version: ${MIN_JQ_VERSION}
        Current jq version: ${currentJQ}"  >&2
        return 1
    fi   
}   

bashCheck (){
    local currentBash=
    currentBash=$(bash --version | head -n1 | awk '{print $4}' | sed -E 's/^([0-9]+\.[0-9]+\.[0-9]).*/\1/')
    if isGEString "$currentBash" "$MIN_BASH_VERSION"; then
        echo "[${FUNCNAME[*]}] bash version condition met." >&2
        return 0
    else
        echo "[${FUNCNAME[*]}] bash version condition not met. 
        Min.    bash version: ${MIN_BASH_VERSION}
        Current bash version: ${currentBash}"  >&2
        return 1
    fi  
    

    return 0
}

whiptailCheck(){
    local currentWhiptail=
    currentWhiptail=$(whiptail --version | sed -n 's/[^0-9.]*\([0-9.]*\).*/\1/p')
    if printf "%s\n%s" "$MIN_WHIPTAIL_VERSION" "$currentWhiptail" | sort -V -C; then 
        echo "[${FUNCNAME[*]}] whiptail version condition met." >&2
        return 0
    else
        echo "[${FUNCNAME[*]}] whiptail version condition not met. 
        Min.    whiptail version: ${MIN_WHIPTAIL_VERSION}
        Current whiptail version: ${currentWhiptail}"  >&2
        return 1
    fi  
}

dependenciesCheck(){

    whiptailCheck
    [[ "$?" != "0" ]] && declare -g "MENU_TYPE"='BASH ' 

    isCommand "${LIST_COMMANDS[@]}" && \
    helmCheck && \
    kubectlCheck && \
    gcloudCheck && \
    jqCheck && \
    bashCheck
    [[ "$?" != "0" ]] && return 1   


    return 0
}