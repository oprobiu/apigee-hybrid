#!/bin/bash
#################### CACHE HANDLING ####################

readCache(){
    # Reads the cache file and echos the keys or values 
    # Output has "", to preserve empty values, using -c
    # $2 = the path/to/cache file that is going to be read with jq
    local cacheFile=$2
    if [[ -z $cacheFile ]] || [[ ! -f $cacheFile ]]; then
        # cacheFile=$CACHED_VALUES_FILE
        echoError "The cacheFile == $cacheFile on '\$2' is non-existent, empty or irregular!" >&2
        return 1
    fi
    local output=($(jq -c "${1}" ${cacheFile}))
    echoDebug "[${FUNCNAME}][${BASH_LINENO[0]}]
            input=$1 
            output=${output[@]}
            cacheFile=$cacheFile">&2
    echo "${output[@]}"
}

removeQuotes(){
    # The input has " " surrounding it and they get removed with sed. 
    # Input is a single string, not an array.
    local checks=
    local output=$(sed -e 's/^"//' -e 's/"$//' <<< "$1")
    checks="$?"
    checkAndDisplayMessage -mt "ERROR" "$checks" "[${FUNCNAME}][sed][${BASH_LINENO[0]}] Unable to sed for input string=${1} and the output=$output"
    if [[ "$checks" == "1" ]]; then return 1; fi
    echo "$output"
    return 0
}



declareCacheValues(){
    # Takes the key-value pairs inside file $1, declares and exports them to env.
    # $1 = path/to/cachefile
    local cacheFile=$1
    local i=
    local cacheKeys=($(readCache "keys_unsorted[]" "${cacheFile}"))
    local cacheValues=($(readCache "values[]" "${cacheFile}"))
    local tempKey=
    local tempValue=
    for ((i=0; i<${#cacheKeys[@]}; i++)); do
        ## remove the quotes with removeQuotes for both cacheKeys and cacheValues. Use tempKey and tempValue to assign the values from the arrays.
        tempKey=$(removeQuotes "${cacheKeys[$i]}")
        # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][removeQuotes] Unable to sed for cacheKey[$i]=${cacheKeys[$i]}"
        if [[ "$?" != "0" ]]; then return 1; fi
        
        tempValue=$(removeQuotes "${cacheValues[$i]}")
        # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][removeQuotes] Unable to sed for cacheValues[$i]=${cacheValues[$i]}"
        if [[ "$?" != "0" ]]; then return 1; fi

        ## Initialization with values from Cache
        declare -g "${tempKey}"="${tempValue}"
        # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][removeQuotes] Unable to sed for cacheValues[$i]=${cacheValues[$i]}"
        if [[ "$?" != "0" ]]; then return 1; fi
        # echoDebug "[${FUNCNAME}]
        #     i           ==  $i
        #     tempKey     ==  $tempKey
        #     tempValue   ==  $tempValue">&2
    done
}

readJSONVariableValues(){
    # $1 == jq pattern
    # $2 == variable name. ${!2} == the variable's value
    local output=
    if [[ -z $1  || -z $2 ]]; then
        echo "[ERROR][${FUNCNAME[*]}] Pattern '$1' and variable '$2' must be non-empty." >&2 
        return 1
    fi
    output=($(jq -c "${1}" <<< "${!2}"))
    [[ "$?" != 0 ]] && return 1
    echo "$output"
    return "$?"
}

declareJSONValues(){
    # Takes the key-value pairs inside variable named $1, declares and exports them to env.
    local i=
    local cacheKeys=
    local cacheValues=
    local tempKey=
    local tempValue=

    cacheKeys=$(readJSONVariableValues "keys_unsorted[]" "$1" )
    cacheValues=($(readCache "values[]" "$1"))

    for ((i=0; i<${#cacheKeys[@]}; i++)); do
        tempKey=$(removeQuotes "${cacheKeys[$i]}")
        [[ "$?" != "0" ]] && return 1
        
        tempValue=$(removeQuotes "${cacheValues[$i]}")
        [[ "$?" != "0" ]] && return 1

        declare -g "${tempKey}"="${tempValue}"
        [[ "$?" != "0" ]] && return 1
    done
}

isFileEmpty(){
    # Checks if $1 file is empty.
    if [ ! -s "${1}" ]; then
        echoDebug "[${FUNCNAME}] File ${1} is empty or non-existent" >&2
        return 0
    else
        return 1
    fi
}

createMissingFile(){
    # if $1 file does not exist, the it will be created.
    local checks=
    # Check if there is a Cache for values, and if not, build it.
    isFileEmpty "$1"
    if [[ "$?" == "0" ]]; then
        mkdir -p "$(dirname "$1")"
        touch "$1"
        checkAndDisplayMessage  -mt "ERROR" "$?" "[${FUNCNAME}][touch] Unable to create file==$1"
        return "$?"
    else
        echoDebug "[${FUNCNAME}] File==$1 already exists.">&2 
        return 1
    fi
}

createAndPopulateFile(){
    # Creates and populates the file IF nonexistent, with the given variable's value
    # $1 = the path/name of the file to be created.
    # $2 = the values to populate the file $1 with.

    createMissingFile "$1"
    checkAndDisplayMessage -mt "DEBUG" "$?" "[${FUNCNAME}][createMissingFile] Failed for file=$1"
    if [[ "$?" != "0" ]]; then return 1; fi
    echoDebug "[${FUNCNAME}] echo file $1 with $2"
    echo "$2" > "$1"
    checkAndDisplayMessage "$?" "[ERROR][${FUNCNAME}][echo] Unable to fill file=$1 with contents=$2"
    if [[ "$?" != "0" ]]; then return 1; fi

    return 0
}

populateCache(){
    # Writes values to to the cache file
    # ${CACHED_VALUES_FILE} is the cache file
    # ${1} is the name of the variable (key)
    # ${2} is the value of the variable (value)
    # ${3} is the location of the cache file

    local key=${1}
    local value=${2}
    local cacheFile=${3}

    jq -e '.' "$cacheFile" >/dev/null
    local evaluator="$?"

    if [[ -z $cacheFile ]] || [[ ! -f $cacheFile ]]; then
        echoError "key==${key}\nvalue==${value}\ncacheFile==${cacheFile}\n on position '$3' is non-existent." >&2
        return 1
    elif [[ "$evaluator" != "0" ]]; then
        echoError "'$cacheFile' does not have a valid JSON structure."
        return 1
    fi

    ## Changes the value for key
    ### in case the $key is not present in the in the $cache file, then add it with its $value, using jq
    local modifiedFile=$(cat "$cacheFile" | jq --arg key "$key" --arg value "$value" '.[$key] = $value')
    echo "$modifiedFile" > "$cacheFile"
    return 0
}



updateCacheWithCurrentEnvValues(){
    # populates the current Cache file. 
    # $1 is the filename variable that holds the location to the Cache file
    # $@ is the array of non-emtpy key NAMES that are present in the ENV.
    local cacheFile=
    local checks=0
    while :; do
        case $1 in 
        -c=|-c|--cache-filename=|--cache-filename)
            if [ -n "${2}" ]; then
                cacheFile=$2
                shift
            else
                echoError "'--cache-filename |-c' requires a non-empty option argument." >&2
                return 1
            fi
        ;;
        *)              # Default case: no more options, therefore break.
            break
        ;;
        esac
        shift
    done

    for key in "$@"; do
        echoDebug "key = $key == ${!key} in file $cacheFile">&2
        createMissingFile "$cacheFile"
        # Get the values from the env variable and populate the cache with them
        populateCache "${key}" "${!key}" "$cacheFile"
        if [[ "$?" == "1" ]]; then
            echoError "Could not populateCache for key=${key}; value=${!key}; file=$cacheFile">&2
            checks=1
            break
        fi
    done 
    return "$checks"

}

updateCachewithEmptyValues() {
    local flagFile=$1
    shift
    local array=("$@")

    for el in "${array[@]}"; do
        declare -g "$el"="" 
        updateCacheWithCurrentEnvValues --cache-filename "$flagFile" "$el"
        checkAndDisplayMessage -mt "ERROR" "$?" "[updateCacheWithCurrentEnvValues] --cache-filename "$flagFile" "$flag""
    done
    return "$?"
}

 #################### MESSAGE HANDLING ####################

checkChecksAndFlag(){
    # Checks if the `checks` variable in a function fails with 1 
    # and output an error message, as well as sending the user backk to the menu.
    # $1 = 1 or 0, the status of the previous command.
    # $2 = The message to be output for failure
    local mess="[${FUNCNAME}] Some checks failed! Routing you back to the Menu..."
    local flag=
    local flagValue=
    # flagCase==Should you log the flag? 0 == yes
    local flagCase=
    local status=
    local flagFile=
    local messageType="INFO"
    ### FLAG HANDLING ###
    while :; do
        case $1 in
            --flag|-f) 
                    flag=$2
                    shift
                ;;
            --flag-value|-fv)               
                    flagValue=$2
                    shift
                ;;
            --flag-case|-fc) 
                    flagCase=$2
                    shift
                ;;
            --flag-file|-ff) 
                    flagFile=$2
                    shift
                ;;
            -mt|--message-type)
                if [ -n "${2}" ]; then
                    messageType=$2
                    shift
                fi
                ;;
            *)
                break
        esac
        shift
    done
    status="$1"

    echoDebug "[${FUNCNAME}]
            flag=$flag
            flagValue=$flagValue
            flagCase=$flagCase
            flagFile=$flagFile
            status=$status">&2
    ## if $2 is not empty, then assign it to the mess.
    if [ -n "$2" ]; then mess="$2"; fi

    if [[ "$status" == "1" ]]; then
        ## if the flag case matches the status, then it gets the flag value
        if [ -n "$flag" ] && [ -n "$flagValue" ]; then
            ## If the status matches the case of the flag, then the flag should be assigned the desired value.
            declare -g "${flag}"="${flagValue}"
        else
            flagFile=
        fi

        if [ -n "$flagFile" ] && [[ "$flagCase" == "0" ]]; then
            updateCacheWithCurrentEnvValues --cache-filename "$flagFile" "$flag"
            checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][updateCacheWithCurrentEnvValues] updateCacheWithCurrentEnvValues --cache-filename "$flagFile" "$flag""
        fi
        checkAndDisplayMessage -mt "$messageType" "$status" "[${FUNCNAME}]$mess "
        return 1
    fi

    return 0
}


####################    MESSAGE HANDLING    ####################
################################################################
