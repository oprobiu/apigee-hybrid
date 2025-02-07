#!/bin/bash
# Functions for deleting components of Apigee Hybrid or erasing it.
# DEPENDENCIES:
# - `cluster_functions.sh` -- deleteCluster().
# - `basic_functions.sh`  
# - `message_functions.sh` 

initDelete(){
    #
    local keyList=("PROJECT_ID" "CLUSTER_NAME" "CLUSTER_LOCATION" "GOOGLE_APIGEE_BASE_URL")
    isKeyListFilledv2 "${keyList[@]}"
    [[ "$?" == "1" ]] && return 1
    return 0
}

deleteOrg(){
    # curl to delete the input Apigee org with the public API
    local projectID=$1

    export TOKEN=$(gcloud auth print-access-token)
    
    curl -v -X "DELETE" \
    -H "Authorization: Bearer $TOKEN" \
    "${GOOGLE_APIGEE_BASE_URL}/organizations/${projectID}?retention=MINIMUM"
    [[ "$?" == "1" ]] && echoError "[${FUNCNAME[*]}] failed to delete org ${projectID}." && return 1

    return 0
}

deleteLB(){

    return 0
}

deleteCache(){
    # deletes the cache generated at runtime
    ## make a backup copy of the current files, including:
    ## - cache/
    ## - hybrid files
    ## - logs 
    local check="0"
    archiveInstallerCache
    [[ "$?" != "0" ]] && echoError "Archiving the Apigee Installer files failed.">&2 && return 1
    ## delete the dirs
    rm -rfv $(dirname "${MAIN_SCRIPT_LOCATION}/${CACHED_VALUES_FILE}") 1> /dev/null
    [[ "$?" != "0" ]] && check="1"
    rm -rfv "${MAIN_SCRIPT_LOCATION}/${APIGEE_HYBRID_BASE}" 1> /dev/null
    [[ "$?" != "0" ]] && check="1"
    # rm -rfv $(dirname "${MAIN_SCRIPT_LOCATION}/${LOGS_FILE}") 1> /dev/null
    # [[ "$?" != "0" ]] && check="1"
    echoInfo "Files erased.">&2
    return "${check}"
}

deleteRuntimeCache(){
    # deletes the cache except the user configs
    ## make a backup copy of the current files, including:
    ## - cache/
    ## - hybrid files
    ## - logs 
    local check="0"
    archiveInstallerCache
    [[ "$?" != "0" ]] && echoError "Archiving the Apigee Installer files failed.">&2 && return 1
    ## delete the dirs
    find "${MAIN_SCRIPT_LOCATION}/$(dirname ${CACHED_VALUES_FILE})" -type f ! -name "$(basename ${CACHED_VALUES_FILE})" -delete 1> /dev/null
    [[ "$?" != "0" ]] && check="1"
    rm -rfv "${MAIN_SCRIPT_LOCATION}/${APIGEE_HYBRID_BASE}" 1> /dev/null
    [[ "$?" != "0" ]] && check="1"
    # rm -rfv $(dirname "${MAIN_SCRIPT_LOCATION}/${LOGS_FILE}") 1> /dev/null
    # [[ "$?" != "0" ]] && check="1"
    echoInfo "Files erased.">&2
    return "${check}"
}

archiveInstallerCache(){
    # # $1 == backup dir
    # # $2 == cachedir
    # [[ -z "$1" ]] && echo 'Backup dir variable on $1 is empty' && return 1
    # [[ -z "$2" ]] && echo 'Cache dir variable on $2 is empty' && return 1
    # [[ -z "$3" ]] && echo 'Helm charts dir variable on $3 is empty' && return 1
    # [[ -z "$4" ]] && echo 'Logs dir variable on $4 is empty' && return 1
    # local backupDir="$1"
    # local cacheDir="$2"
    # local hybridDir="$3"
    # local logsDir="$4"
    local backupOutput=

    mkdir "${MAIN_SCRIPT_LOCATION}/${BACKUP_DIR}"
    [[ "$?" != "0" ]] && echoWarning "Creating the dir ${MAIN_SCRIPT_LOCATION}/${BACKUP_DIR} failed.">&2
    
    backupFileList "${MAIN_SCRIPT_LOCATION}/${BACKUP_DIR}/backup_$(date +%s).tar.gz" \
        "$(dirname "${MAIN_SCRIPT_LOCATION}/${CACHED_VALUES_FILE}")" \
        "${MAIN_SCRIPT_LOCATION}/${APIGEE_HYBRID_BASE}" \
        "$(dirname "${MAIN_SCRIPT_LOCATION}/${LOGS_FILE}")" 
    [[ "$?" != "0" ]] && echoError "Creating all the backups failed.">&2 && return 1

    echoInfo "Archive created at ${MAIN_SCRIPT_LOCATION}/${BACKUP_DIR}">&2
    return 0
}

backupFileList(){
    # $1 == backup location
    # $@ == array of files to archive
    local backupPath="$1"
    shift
    local array=("$@")
    local check="0"
    for file in "${array[@]}"; do
        backupFile "$backupPath" "$file"
        [[ "$?" != 0 ]] && echo "Failed to backup file '$file' ---> '$backupPath'.">&2 && check="1" && continue
        echo "Backup for file '$file' to '$backupPath' was successful." >&2
    done

    return "$check"
}


backupFile(){
    # archive dir at $2 to the location at $1
    [[ -z "$1" || -d "$1" ]] && echo 'Backup dir variable on $1 is empty or not a directory.'>&2 && return 1
    [[ -z "$2" ]] && echo 'Target path variable on $2 is empty.'>&2 && return 1

    tar -czvf "${1}" "$2"
    [[ "$?" != "0" ]] && echo "Could not archive '${2}' at '${1}'">&2 && return 1
    return 0
}



mainDeleteSequence() {
    # main function to delete based on the input options
    # local eraseList=("$@")
    ## init sequence
    initDelete
    [[ "$?" == "1" ]] && return 1
    ## check if first value of array is empty
    local confirmMessage='
    
    Are you sure you want to proceed? This action cannot be undone.

    Please confirm (yes/no) [Y/n]: '

    [[ -z "$1" ]] && shift 1

    while :; do
        case ${1^^} in
            "CLUSTER")
                echoWarning "\n[${FUNCNAME[*]}] This option will erase your cluster '$CLUSTER_NAME' in project '$PROJECT_ID', location '$CLUSTER_LOCATION'.\n" >&2
                confirmYes "$confirmMessage"
                [[ "$?" == "1" ]] && shift && continue

                deleteCluster \
                    --project "$PROJECT_ID" \
                    --cluster "$CLUSTER_NAME" \
                    --region "$CLUSTER_LOCATION" \
                    --runtime-cachefile "/dev/null"
                [[ "$?" == "1" ]] && return 1
            ;;
            "ORG")
                echoWarning "\n[${FUNCNAME[*]}] This option will erase your Apigee project '$PROJECT_ID'.\n" >&2
                confirmYes "$confirmMessage"
                [[ "$?" == "1" ]] && shift && continue
                deleteOrg "${PROJECT_ID}"
                [[ "$?" == "1" ]] && return 1
            ;;
            "LB")
                echoWarning "\n[${FUNCNAME[*]}] This option will erase your Apigee Load Balancer in project '$PROJECT_ID'.\n" >&2
                confirmYes "$confirmMessage"
                [[ "$?" == "1" ]] && shift && continue
                echoWarning "[${FUNCNAME[*]}] Deleting LB:" >&2 
                deleteLB
                [[ "$?" == "1" ]] && return 1
            ;;
            "CACHE")
                echoWarning "\n[${FUNCNAME[*]}] This option will erase your file at:\n \
                $(dirname "${MAIN_SCRIPT_LOCATION}/${CACHED_VALUES_FILE}")\n \
                ${MAIN_SCRIPT_LOCATION}/${APIGEE_HYBRID_BASE}\n \
                $(dirname "${MAIN_SCRIPT_LOCATION}/${LOGS_FILE}") \
                " >&2

                confirmYes "$confirmMessage"
                [[ "$?" == "1" ]] && shift && continue
                deleteCache
                [[ "$?" == "1" ]] && return 1
            ;;
            "RUNTIME-CACHE")
                echoWarning "\n[${FUNCNAME[*]}] This option will erase your file at:\n \
                $(dirname "${MAIN_SCRIPT_LOCATION}/${CACHED_VALUES_FILE}") -- except the $(basename ${CACHED_VALUES_FILE}) file $\n \
                ${MAIN_SCRIPT_LOCATION}/${APIGEE_HYBRID_BASE}\n \
                $(dirname "${MAIN_SCRIPT_LOCATION}/${LOGS_FILE}") \
                " >&2
                confirmYes "$confirmMessage"
                [[ "$?" == "1" ]] && shift && continue
                deleteRuntimeCache
                [[ "$?" == "1" ]] && return 1
            ;;
            *)
                break
            ;;
        esac
        shift
    done

    return 0 
}


