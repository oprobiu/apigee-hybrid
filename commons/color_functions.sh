
#!/bin/bash
#################### MESSAGE HANDLING ####################

colorArray(){
    # input json object with the names of the variables
    # output=array
    local jsonObject="$1"
    local jsonNameKey="$2"
    local jsonColorKey="$3"
    local i=
    local arrayFlag=
    local arrayName=

    mapfile -t arrayName < <(getJsonKeyValuev2 "$jsonNameKey" "$jsonObject")
    mapfile -t arrayFlag < <(getJsonKeyValuev2 "$jsonColorKey" "$jsonObject")        
        
    # echoDebug "[${FUNCNAME}] arrayName size==${#arrayName[@]}
    #     arrayName==${arrayName[*]}">&2

    # echoDebug "[${FUNCNAME}] arrayFlag size==${#arrayFlag[@]}
    #     arrayFlag=${arrayFlag[*]}">&2

    for ((i=0; i<${#arrayName[@]}; i++)); do
        colorString "$(selectColor ${!arrayFlag[$i]})" "${arrayName[$i]}"
    done
    return 0
}

colorString(){
    # $1 = color
    # $2 = string
    if [ -z "$1" ]; then 
        echo "${2}"
    else
        echo "${1}${2}\033[0m"
    fi
    
    return 0
}

selectColor(){
    # $1 = string
    # output = color
    local type="${1^^}"
    local types=("TRUE" "AVAILABLE" "FAILED" "FALSE")
    case $type in
        "TRUE")
            echo '\033[1;92;107m'
        ;;
        "AVAILABLE")
            echo '\033[1;94;107m'
        ;;
        "FAILED"|"FALSE")
            echo '\033[1;91;107m'
        ;;
        *)
            echo ""
        ;;
    esac
    return 0
}

colorArrayv2() {
    # outputs the corresponding color for the option, based on the corresponding flag for the key
    # input json object with the names of the variables
    # output=array
    local jsonObject="$1"
    local jsonNameKey="$2"
    local preffixFlag="$3"
    local selectKey="$4"
    local suffixFlag="$5"
    local i=
    local selectedFlag=

    mapfile -t arrayName < <(getJsonKeyValuev2 "$jsonNameKey" "$jsonObject")
    for ((i=0; i<${#arrayName[@]}; i++)); do
        # for each key, select its corresponding flag
        selectedFlag=$(jq -r "${preffixFlag} | select(${selectKey} == \"${arrayName[$i]}\") | ${suffixFlag}"  <<< "$jsonObject")

        colorString "$(selectColor ${!selectedFlag})" "${arrayName[$i]}"
        # echoDebug "[${FUNCNAME}] loop:
        #     arrayName[$i]   == ${arrayName[$i]}
        #     prefixFlag      == $prefixFlag
        #     selectKey       == $selectKey
        #     suffixFlag      == $suffixFlag
        #     selectedFlag    == $selectedFlag">&2
    done
    return 0
}
