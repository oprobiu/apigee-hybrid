#!/bin/bash

# Function to dynamically replace a property in a YAML section
replaceSedRangeYaml() {
    local rangeStart=$1
    local rangeEnd=$2
    local property=$3
    local oldValue=$4
    local newValue=$5
    local filePath=$6
    echoDebug "[${FUNCNAME}] Input:
    rangeStart=$1
    rangeEnd=$2
    property=$3
    oldValue=$4
    newValue=$5
    filePath=$6">&2

    # Use sed to replace the property value in the specified section
    sed -i "/$rangeStart:/,/$rangeEnd/ s/$property: $oldValue/$property: $newValue/" "$filePath" >&2
    checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME[*]}]sed failed"
    return "$?"
}

simpleGrepSEdExtrF2V(){
    # Extracts based on the input pattern $1 a string matched inside a file $2 and outputs in a variable
    # [WARNING] avoid :
    local pat=$1
    local file=$2 
    # local sedResult=
    grep -o "$pat" "$file" | sed 's/\$//g'
    
    # sedResult=($(sed -r "s:.*${pat}::g"))
    # sedResult=($(sed -r 's/.*\$(.*)".*/\1/g' file.txt))

}


simpleGrepSEdExtrV2V(){
    # Extracts based on the input pattern $1 a string matched inside a file $2 and outputs in a variable
    # [WARNING] avoid :
    local pat=$1
    local var=$2 
    # local sedResult=
    grep -o "$pat" <<<"$var" | sed 's/\$//g'
    checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][grep -o "$pat" <<<"$var" | sed 's/\$//g']"
    return "$?"
}


replaceKeysWithTheirValuesInFile(){
    # Replaces a key that starts with $ with the value of that key and no $.
    # ex. $ANALYTICS_REGION is replaced with europe-west1
    # $1 = /path/to/file
    # $@ = array of variables to replace
    
    local file="$1"
    shift 1
    local array=("$@")
    local check=0

    for key in "${array[@]}"; do 
        sed -r -i 's:\$('"$key"'):'"${!key}"':g' "$file"
        checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][sed -r -i 's:\$('"$key"'):'"${!key}"':g' "$file"]"
        if [[ "$?" == "1" ]]; then check=1; fi
    done

    return "$check"
}



outputProcessorKeyValue() {
    # Takes the output as input and checks for the desired key's value and echo's it.
    # $1 = key's name 
    # $2 = output to be processed
    # [FUTURE] USE JQ INSTEAD AND REWORK THE PROCESS

    local key=${1}
    local value=
    local output=${2}
    ############ Pre-checks ############
    ####################################

    if [[ -z "${key}" ]] || [[ -z "${output}" ]]; then
        echoError "[${FUNCNAME}] One of these are empty: 
        key == ${key}
        output == ${output}" >&2 
        return 1
    else
        ## [FUTURE] create checks for these grep results, as it should only be one result and from the variable
        local value=$(echo "${output}" | grep -o "\"${key}\": \"[^\"]*\"" | sed "s/\"${key}\": \"//; s/\"//" )
        echo "${value}"
        return 0
    fi
}

getJsonKeyValue() {
    # Takes the an input json variable's value and checks for the desired key's value and echo's it.
    # $1 = key's name (the complete path to the key)
    # $2 = json input to be processed
    local key=${1}
    local value=
    local jsonInput=${2}
    if [[ -z "${key}" ]] || [[ -z "${jsonInput}" ]]; then
        echoError "[${FUNCNAME}]
        One of these values are empty:
        key         = ${key}
        output      = ${output}" >&2 
        return 1
    else
        local value=$(jq -r "$key" <<< $jsonInput )
        echo "${value}"
        return "$?"
    fi
}

getJsonKeyValuev2() {
    # Takes the an input json variable's value and checks for the desired key's value and echo's it.
    # $1 = key's name (the complete path to the key)
    # $2 = json input to be processed
    local key=${1}
    local value=
    local jsonInput=${2}
    if [[ -z "${key}" ]] || [[ -z "${jsonInput}" ]]; then
        echoError "[${FUNCNAME}]
        One of these values are empty:
        key         = ${key}
        jsonInput      = ${jsonInput}" >&2 
        return 1
    else
        # local value=($(jq -r "$key" <<< $jsonInput ))
        # echo "${value[@]}"
        # echoDebug "${#svalue[@]}">&2
        jq -r "$key" <<< $jsonInput | while read obj; do
            # echoDebug "[getJsonKeyValuev2]
            # object content:         ${obj}
            # array length of obj:    ${#obj[@]}">&2
            echo "$obj"
        done
        return "$?"
    fi
}

