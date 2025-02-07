#!/bin/bash



menuUserVariables() {
    # Ask user to fill these environments, as they are obligatory.
    # The menu for changing User Variables.
    local PS3="
    Choose a variable to update or quit by choosing the 'Return' option: "
    local cachedValuesFile="$1"
    # default value
    isVariableFilled "cachedValuesFile"
    if [[ "$?" == "1" ]]; then 
        echoWarning "[${FUNCNAME[*]}][isVariableFilled] assigning the default value $CACHED_VALUES_FILE"
        cachedValuesFile="$CACHED_VALUES_FILE" 
    fi

    ## PULL THE CURRENT VALUES FROM THE CACHE.
    local cacheKeys=($(readCache "keys_unsorted[]" "${cachedValuesFile}"))
    local cacheValues=($(readCache "values[]" "${cachedValuesFile}"))
    # local options=("${cacheKeys[@]}" "Quit")
    local temp=($(for el in "${cacheKeys[@]}"; do removeQuotes "$el"; done)) 
    local options=( "${temp[@]}" "Return")

    # Pre-check to ensure that the cache variables are declared in this environment
    declareCacheValues "${cachedValuesFile}"
    checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME[*]}][declareCacheValues] file==$cachedValuesFile"
    if [[ "$?" != "0" ]]; then return 1; fi

    # Display Current values    
    echoInfo "
            The current state of the environment variables:">&2
    displayValuesInArrayv2 ${cacheKeys[@]} 

    select opt in "${options[@]}"; do
        # Check if opt is a valid string
        if [[ -z $opt ]]; then
            echoWarning "Invalid option selected. Please try again."
            continue
        fi
        # Quit if option is equal to Quit.
        if [[ $opt == "Return" ]]; then
            # return 0
            return 0
        fi
        # declare the variables and export them
        declare +x "$opt"="$(AskValueVariable $opt)"                              
        declare -g "${opt}=${!opt}"  
        # Updates the cache for the key with the new value" 
        populateCache "${opt}" "${!opt}" $cachedValuesFile
        checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME[*]}][populateCache] Failed to populate cache for:
        key     ==  $opt
        value   ==  ${!opt}
        file    ==  $cachedValuesFile"
        if [[ "$?" != "0" ]]; then return 1; fi
        # Display Current values
        displayValuesInArrayv2 ${cacheKeys[@]}
        # Display the Quit option
        echo "$((${#cacheKeys[@]}+1))) Return"
    done
}


whiptailUserVars(){
    local userChoice=
    local options=()
    local i=0
    local temp=
    local menuTitle="$1"
    local message="$2"
    local cachedValuesFile="$3"
    local inputResult=
    # default value
    if [[ -z "$cachedValuesFile" ]]; then 
        echo "[${FUNCNAME[*]}][isVariableFilled] assigning the default value ${CACHED_VALUES_FILE}">&2
        cachedValuesFile="$CACHED_VALUES_FILE" 
    fi

    ## PULL THE CURRENT VALUES FROM THE CACHE.
    local cacheKeys=($(readCache "keys_unsorted[]" "${cachedValuesFile}"))
    local cacheValues=($(readCache "values[]" "${cachedValuesFile}"))
    ## remove quotes
    temp=($(for el in "${cacheKeys[@]}"; do removeQuotes "$el"; done))
    cacheKeys=("${temp[@]}")
    # temp=($(for el in "${cacheValues[@]}"; do removeQuotes "$el"; done))
    # cacheValues=("${temp[@]}")

    ## FORMAT THE INPUT OPTIONS
    for ((i=0; i<${#cacheKeys[@]}; i++)); do
        options+=("${cacheKeys[$i]}" "${cacheValues[$i]}" )
    done

    # Pre-check to ensure that the cache variables are declared in this environment
    declareCacheValues "${cachedValuesFile}"
    if [[ "$?" != "0" ]]; then
        echo "[ERROR][${FUNCNAME[*]}] declareCacheValues ${cachedValuesFile} failed.">&2
        return 1
    fi

    ## flush the user input
    flushInput > /dev/null
    while :; do
        # infobox
        userChoice=$(whiptailMenu --title "${menuTitle}" \
        --message "${message}" \
        --options "${options[@]}")
        [[ "$?" != '0' ]] && return 1

        [[ -z "$userChoice" ]] && break

        # declare the variables and export them
        inputResult=$(whiptailInputBox \
        --title "Change the value of '$userChoice'." \
        --message "Please insert the new value for '$userChoice'. Current value is '${!userChoice}'." \
        --default "")
    
        [[ "$?" != '0' ]] && return 1
        [[ -z "$userChoice" ]] && continue

        declare -g "${userChoice}=${inputResult}" 
        populateCache "${userChoice}" "${!userChoice}" "$cachedValuesFile"
        [[ "$?" != '0' ]] && echo "[ERROR][${FUNCNAME[@]}] populateCache '${userChoice}' '${!userChoice}'." && return 1

        ## PULL THE CURRENT VALUES FROM THE CACHE.
        local cacheKeys=($(readCache "keys_unsorted[]" "${cachedValuesFile}"))
        local cacheValues=($(readCache "values[]" "${cachedValuesFile}"))
        ## remove quotes
        temp=($(for el in "${cacheKeys[@]}"; do removeQuotes "$el"; done))
        cacheKeys=("${temp[@]}")
        # temp=($(for el in "${cacheValues[@]}"; do removeQuotes "$el"; done))
        # cacheValues=("${temp[@]}")
        options=()
        ## FORMAT THE INPUT OPTIONS
        for ((i=0; i<${#cacheKeys[@]}; i++)); do
            options+=("${cacheKeys[$i]}" "${cacheValues[$i]}" )
        done
    done

    return 0
}
