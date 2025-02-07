#!/bin/bash

compareTwoStrings(){
    # compares two input strings to see if they are the same
    echoDebug "[${FUNCNAME[*]}] \$1==$1 vs \$2==$2" >&2
    if [[ "${1}" == "${2}" ]]; then
        return 0
    else 
        return 1
    fi
}

checkFileName() {
    # $1 = input file with path
    # $2 = desired name
    if [ "${1##*/}" == "$2" ]; then
        return 0
    else
        return 1
    fi
}

getCurlStatus() {
    # $1 = the URL to call
    # $TOKEN is stored in the environment and should be generated already
    local token="$(gcloud auth print-access-token)"
    local curlStatusCode=
    if [[ -z "$token" ]]; then return 1; fi
    curlStatusCode=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $token" \
        $1)
    echo "${curlStatusCode}"
    return 0
}


isKeyListFilled(){
    # Checks for a given array of env variables keys if they have a value, using the isVariabileFilled function.
    # returns 1 if one is not. Else return 0
    # $@ = the array
    local listCheck=0
    local key=
    echoDebug "[${BASH_LINENO[0]}][${FUNCNAME[*]}] The keyArray==${@}"
    for key in "$@"; do
        if ! isVariableFilled "$key"; then
            echoError "[${FUNCNAME[*]}][isVariableFilled] key == $key is not filled!"
            listCheck=1
        fi
    done

    if [[ "$listCheck" == "1" ]]; then
        return 1
    fi 
    return 0
}

isKeyListFilledv2(){
    # Checks for a given array of env variables keys if they have a non-'null' or empty value, using the isVariabileFilled and isVariableNull functions.
    # returns 1 if one is not filled properly.
    # $@ = the array
    local listCheck=0
    local key=
    echoDebug "input keyArray==${@}"
    for key in "$@"; do
        if ! isVariableFilled "$key" || isVariableNull "$key"; then
            echoError "key == $key = '${!key}' is either null or empty." >&2
            listCheck="1"
        fi
    done

    if [[ "$listCheck" == "1" ]]; then
        return 1
    fi 
    return 0
}

isVariableNull(){
    # Is the input variable equal to 'null'?
    if [[ "${!1,,}" == 'null' ]]; then
        # if null, then warn user to not proceede further
        # echo "[ERROR][isVariableFilled] ${1} variable is empty!" >&2 
        echo "[${FUNCNAME[*]}] $1 variable is 'null'." >&2
        return 0
    fi
    return 1
}

isVariableFilled() {
    # Is the input variable filled?

    local var=${1}
    if [ -z "${!var}" ]; then
        # if empty, then warn user to not proceede further
        # echo "[ERROR][isVariableFilled] ${1} variable is empty!" >&2 
        echoWarning "[${FUNCNAME[*]}] $1 variable is empty." >&2
        return 1
    fi
    return 0
}


displayValuesInArray() {
    # Echo the values of the input array 
    local array=("$@")
    local i=

    # Display the current key-value pairs
    for ((i=0; i<${#array[@]}; i++)); do  
        echo "$((i+1))) ${array[$i]}=${!array[$i]}"                     
    done

}

displayValuesInArrayv2() {
    # Echo the values of the input array, and processes them with removeQuote
    local array=("$@")
    local tempKey=
    local i=

    # Display the current key-value pairs
    for ((i=0; i<${#array[@]}; i++)); do  
        tempKey=$(removeQuotes "${array[$i]}")
        checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][removeQuotes] for ${array[$i]}"
        echo "$((i+1))) ${tempKey}=${!tempKey}" >&2                    
    done

}
displayArray(){
    # $1 == prefix message
    # $2 == suffix message  
    #input == #@
    # echos the array
    local prefix=$1
    local suffix=$2
    shift 2
    local array=("$@")

    # Display
    for element in "${array[@]}"; do
        echo "${prefix}${element}${suffix}" 
    done

    return "$?"    
}
displayMenuOptions(){
    # $1 == prefix message
    # $2 == suffix message  
    #input == #@
    # echos the array
    local prefix=$1
    local suffix=$2
    shift 2
    local array=("$@")
    local i=
    # Display
    for ((i=0; i<${#array[@]}; i++)); do
        echo -e "${prefix}${i}) ${array[$i]}${suffix}" 
    done
    return "$?"    
}

flushInput(){
    while read -r -t 0.1; do :; done
    return "$?"
}


confirmYes(){
    # Asks users to confirm if they want to proceed further of if they want to go back
    #$1 = the prompt message.
    local userInput=
    flushInput
    while true; do
        read -p "$1" userInput
        case "${userInput^^}" in
            NO|N)
                return 1
            ;;
            YES|Y)
                return 0
            ;;
            *)
                echo -e "[${FUNCNAME}] Invalid input. [Y|n] ">&2
            ;;
        esac
    done
}



verifyIPv4() {
    local ipv4="$1"
    if [[ $ipv4 =~ ^(([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]{1,2}|1[0-9]{2}|2[0-4][0-9]|25[0-5])$ ]]; then
        echoDebug "[${FUNCNAME}] $ipv4 is a valid IPv4 format" >&2
        return 0
    else
        echoDebug "[${FUNCNAME}] $ipv4 is an invalid IPv4 format" >&2
        return 1
    fi
}


isValidVersion(){
    ## Checks if $1 is under the format MAJOR.MINOR.PATCH or MAJOR.MINOR
    # if [[ "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then

    if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "MAJOR.MINOR.PATCH"
        return 0
    elif [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "MAJOR.MINOR"
        return 0
    else
        echo "INVALID"
        return 1
    fi
}
isMMVersion(){
    ## checks if the version format is MAJOR.MINOR or not
    if [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi
    return 1
}

isMMPVersion(){
    ## checks if the version format is MAJOR.MINOR or not
    if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 0
    fi
    return 1
}


handleVersions(){
    local refVer=
    local ver=
    local refStr=
    local str=
    local i=
    while :; do
        # echo -e "\n\nPOSTION \$1==$1\n\$2==$2\n" >&2
        case $1 in
            --ref-version|-r)
                while [[ ! "$2" =~ ^- ]] && [[ ! -z "$2" ]]; do
                    # if [ -z "$2" ]; then
                    #     echo "Flag '--ref-version|-rv' requires a non-empty value">&2
                    #     return 1
                    # fi
                    isValidVersion "$2" >&2 
                    [[ "$?" != "0" ]] && echo "Flag '--ref-version|-rv' requires a MAJOR.MINOR[.PATCH] format.">&2 && return 1
                    refVer+=("$2")
                    shift
                done
            ;; 
            --version|-v)
                if [ -z "$2" ]; then
                    echo "Flag '--version|-v' requires a non-empty value">&2
                    return 1
                fi
                isValidVersion "$2" >&2 
                [[ "$?" != "0" ]] && echo "Flag '--version|-v' requires a MAJOR.MINOR[.PATCH] format.">&2 && return 1
                ver="$2"
                shift
            ;;
            --ref-string|-s)
                while [[ ! "$2" =~ ^- ]] && [[ ! -z "$2" ]]; do
                    # if [ -z "$2" ]; then
                    #     echo "Flag '--ref-string|-s' requires a non-empty value">&2
                    #     return 1
                    # fi
                    refStr+=("$2")

                shift
                done
            ;;
            # --string|-s)
            #     if [ -z "$2" ]; then
            #         echo "Flag '--string|-s' requires a non-empty value">&2
            #         return 1
            #     fi
            #     str="$2"
            #     shift
            # ;;
            *)
                break
            ;;
        esac
    shift 
    done

    
    ## remove empty values
    [ -z "${refVer[0]}" ] && unset 'refVer[0]' >&2 
    [ -z "${refStr[0]}" ] && unset 'refStr[0]' >&2 

    # for eachVer in "${refVer[@]}"; do
    for ((i=1; i<="${#refVer[@]}"; i++)); do
        # echo "[DEBUG] '${refVer[$i]}'=='$ver'" >&2
        if [[ "${refVer[$i]}" == "$ver" ]]; then
            echo "${refStr[$i]}"
            return 0
        fi

    done 

    echo "[ERROR] Version '$eachVer' not matched." >&2
    return 1
    # isMMPVersion "$ver" && ver="${ver%.*}"
    # isMMPVersion "$refVer" && refVer="${refVer%.*}"

    # if [[ "$ver" >= "$refVer" ]]; then
    #     echo "$str"
    #     return 0
    # else
    #     echo "$refStr"
    #     return 1
    # fi



}


numberArrayElements(){
    ## Creates a new array that has numbered each of the elements in the old array
    ## (A B) --> (1 A 2 B)
    local iA=("$@")
    local oA=

    for ((i = 0; i < ${#iA[@]}; i++)); do 
        oA+=($(($i + 1)))
        oA+=("${iA[$i]}")
    done
    # oA="${oA[@]:1}"
    # echo "${oA[@]}"
    printf "%s\0" "${oA[@]}"
}