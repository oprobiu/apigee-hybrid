
#!/bin/bash
# INPUT LOGS FILE == $ABS_LOGS_FILE

#################### MESSAGE HANDLING ####################
echoDebug(){
    # $1 == message
    if [[ "${DEBUG_MODE}" == "true" ]]; then 
        echo -e "\033[1;92;100m
        [DEBUG][$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")][PID $$][LINE: ${BASH_LINENO[0]}][${FUNCNAME[*]}] ${1}
        \033[0m\n" | tee -a "${ABS_LOGS_FILE}"
    else
        echo -e "\033[1;92;100m[DEBUG]
        [$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")][PID $$][LINE: ${BASH_LINENO[0]}][${FUNCNAME[*]}] ${1}
        \033[0m\n" >> "${ABS_LOGS_FILE}"
    fi
}

echoError(){
    # $1 == message
    echo -e "\033[1;91;47m[ERROR][$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")][LINE: ${BASH_LINENO[0]}][${FUNCNAME[@]:1:${#FUNCNAME[@]}-2}] ${1}\033[0m\n" | tee -a "${ABS_LOGS_FILE}"
}

echoTest(){
    # $1 == message
    if [ -n "$1" ]; then
        IN="$1"
        echo -e "\033[1;91;47m [ECHO TEST] ${1} \033[0m\n"
    else
        read IN # This reads a string from stdin and stores it in a variable called IN
        echo -e "\033[1;91;47m [ECHO TEST] ${IN} \033[0m\n"
    fi
    
}

echoInfo(){
    # $1 == message
    echo -e "\033[1;90;47m[INFO][$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")] ${1}\033[0m\n" | tee -a "${ABS_LOGS_FILE}"
}

echoWarning(){
    # $1 == message
    echo -e "\033[1;93;100m[WARNING][$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")] ${1}\033[0m\n" | tee -a "${ABS_LOGS_FILE}"
}


### ### ### ##


checkAndDisplayMessage(){
    # Checks if the `checks` variable in a function fails with 1 
    # and output an error message,
    # $1 = 1 or 0, the status of the previous command.
    # $2 = The message to be output for failure
    local mess="Some checks failed!"
    local messageType="INFO"

    while :; do
        case $1 in 
        -mt|--message-type)
            if [ -n "${2}" ]; then
                messageType="${2^^}"
                shift
            fi
        ;;
        *)
            break
        ;;
        esac
        shift
    done
    ## if $2 is not empty, then assign it to the mess.
    [ -n "$2" ] && mess="$2"
    
    ## If checks will be 1, then one of the conditions above failed.
    if [[ ${1} != "0" ]]; then
        case "$messageType" in
            "INFO")
                echoInfo "$2" >&2
            ;;
            "DEBUG")
                echoDebug "$2" >&2
            ;;
            "WARNING")
                echoWarning "$2" >&2;
            ;;
            "ERROR")
                echoError "$2" >&2;
            ;;
        esac
        return 1
    fi
    return 0
}

logMessage(){
    local mess="Something failed"
    local messageType="ERROR"
    if [[ "$1" == "-t" || "$1" == "--message-type" ]] && [ -n "$2" ]; then 
        messageType="${2^^}"
        shift 2
    fi
    [ -n "$1" ] && mess="$1"
    
    case "${messageType^^}" in
        "INFO"|"I")
            echoInfo "$mess" >&2
        ;;
        "DEBUG"|"D")
            echoDebug "$mess" >&2
        ;;
        "WARNING"|"WARN"|"W")
            echoWarning "$mess" >&2;
        ;;
        "ERROR"|"ERR"|"E")
            echoError "$mess" >&2;
        ;;
        *)
            echo "[${FUNCNAME[*]}] Invalid log message case messageType==${messageType}">&2
    esac
    return 0

}


TransitionEffect() {
    # Transition Effects for menus
    local delay=0.1
    local spin_chars="/-\|"
    local spin_index=0
    local start_time=$(date +%s)
    local duration=$1 # run for input amount of seconds
    local message="Loading..."

    if [[ ! -z "$2" ]]; then message=$2; fi

    while [ $(($(date +%s) - start_time)) -le $duration ]; do
        local spin_char=${spin_chars:$spin_index:1}
        printf "\r${message} [$spin_char]"
        spin_index=$(( (spin_index + 1) % ${#spin_chars} ))
        sleep $delay
        # if [ $(($(date +%s) - start_time)) -ge $duration ]; then
        #     break
        # fi
    done
    printf "\n"
    return 0
}



