#!/bin/bash

loopCurl() {
    # Do a Curl after a certain input value in a loop, until the desired condition is met
    # $1 = The curl URL WITH https:// added 
    local url=
    local leftSide=
    local leftSideValue=                                
    local expectedValue=
    local method="GET"
    local header=
    local body=
    local loopWaitTime=
    local TMaxWaitTime=

    ## Declare the flags' presence
    local flag_leftSide=false
    local flag_expectedValue=false
    local flag_loopWaitTime=false
    local flag_TMaxWaitTime=false  

    ## for execution
    local curlOutput=
    local start_time=$(date +%s)

    # Handle each flag
    while :; do
        case $1 in
            -h|-\?|--help)
                echoInfo " #[HELP OPTIONS]
        -l|-left|--key                          = the key's name for which the value is extracted.
        -r|-right|--expectedValue               = the expected valued for the key.
        -X|--method                             = the method for curl. Default is GET.
        -H|--header                             = the header for the curl.
        -d|--body                               = the body for the curl.
        -lWT|--loopWaitTime                     = how long should a loop last [seconds]
        -TMWT|--TMaxWaitTime                    = how long should the user wait in total before stopping [seconds]
                "
                exit
                ;;
            -l|-left|--key)
                # ensure that it is specified
                if [ "${2}" ]; then
                    leftSide=$2
                    flag_leftSide=true
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '-l|-left|--key' requires a non-empty option argument" >&2
                fi

                ;;
            -r|-right|--expectedValue)
                # ensure that it is specified
                if [ "${2}" ]; then
                    expectedValue=$2
                    flag_expectedValue=true
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '-r|-right|--expectedValue' requires a non-empty option argument" >&2
                fi
                ;;
            -X|--method)
                # specified or by default make sure it is GET
                method=$2
                shift
                ;;
            -H|--header)
                # optional
                header=$2
                shift
                ;;
            -d|--body)
                # optional
                body=$2
                shift
                ;;
            -lWT|--loopWaitTime)
                # [WIP] ensure that it is specified
                if [ "${2}" ]; then
                    loopWaitTime=$2
                    flag_loopWaitTime=true
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '-lWT|--loopWaitTime' requires a non-empty option argument" >&2
                fi
                ;;
            -TMWT|--TMaxWaitTime)
                # ensure that it is specified
                if [ "${2}" ]; then
                    TMaxWaitTime=$2
                    flag_TMaxWaitTime=true
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '-TMWT|--TMaxWaitTime' requires a non-empty option argument" >&2
                fi
                ;;
            *)
                break
        esac
        shift
    done

    # Assign the URL passed
    url=${1}

    ############ Pre-check flags ############  
    if [ "$flag_leftSide" = "false" ] || [ "$flag_rightSide" = "false" ] || [ "$flag_loopWaitTime" = "false" ] || [ "$flag_TMaxWaitTime" = "false" ]; then
        echoError "[${FUNCNAME[*]}] One of these flags are missing:
        -l=${leftSide}
        -r=${expectedValue}
        -lWT=${loopWaitTime}
        -TMWT=${TMaxWaitTime}
        leftSide        = ${leftSide}
        expectedValue   = ${expectedValue}
        method          = ${method}
        header          = ${header}
        body            = ${body}
        url             = ${url}
        loopWaitTime    = ${loopWaitTime}
        TMaxWaitTime    = ${TMaxWaitTime}
        url             = ${url}">&2
        return 1 
    fi
    checks=0

    # Execution
    while (($checks == 0))
    do
        curlOutput=$(curl -X "${method}" -H "${header}" -d "${body}" "${url}" --silent --show-error)

        echoDebug "[${FUNCNAME[*]}] The following curl:
            -X "${method}" 

            -H "${header}" 

            -d "${body}" 

            "${url}"
            =====================================
            Outputs the following:
                $curlOutput
            =====================================">&2

        # processing curl output
        leftSideValue=$(getJsonKeyValue "${leftSide}" "${curlOutput}")
        compareTwoStrings "${leftSideValue}" "${expectedValue}"
        checks="$?"
        checkAndDisplayMessage -mt "DEBUG" "$checks" "[${FUNCNAME[*]}]
        leftSideValue==$leftSideValue vs expectedValue==$expectedValue" >&2

        if [[ $checks == "0" ]]; then
            echoDebug "[${FUNCNAME[*]}] The key==$leftSide has the expected value $leftSideValue"
            break
        # Check if the wait time has been exceeded
        elif [ $(($(date +%s) - start_time)) -ge "$TMaxWaitTime" ]; then
            # [WIP] ERROR MESSAGE
            echoWarning "[${FUNCNAME[*]}] Wait time exceeded, exiting loop...">&2
            break
        fi

        # Wait for loopWaitTime seconds to check again
        TransitionEffect ${loopWaitTime}
    done
    return "$checks"
}

loopCurlv2(){
    local url=
    # flags
    local headers=
    local body=
    local method="GET"
    local totalWaitTime=1000
    local pollingInterval=30
    local key=
    local expectedValue= 
    local cMessage=
    #
    local start_time=
    local curlOutput=
    local keyValue=
    local i=0

# Handle each flag
    while :; do
        case $1 in
            -H)
                if [ "$2" ]; then 
                    headers+=("-H" "$2")
                    shift
                    echoDebug "[${FUNCNAME[*]}] Input for headers == $2. headers==${headers[*]}." >&2
                else
                    echoError "[${FUNCNAME[*]}] Invalid Header=="$2"." >&2
                    return 1
                fi
                ;;
            -d)
                if [ "$2" ]; then 
                    body="$2"
                    shift
                    echoDebug "[${FUNCNAME[*]}] body==$body. Input == $2">&2
                else
                    echoError "[${FUNCNAME[*]}] Invalid body=="$2".">&2
                    return 1
                fi
                ;;
            -X)
                if [ "$2" ]; then 
                    method="$2"
                    shift
                    echoDebug "[${FUNCNAME[*]}] method==$body. Input == $2">&2
                else
                    echoError "[${FUNCNAME[*]}] Invalid method=="$2".">&2
                    return 1
                fi
                ;;
            --total-wait-time)
                if [ "$2" ]; then 
                    totalWaitTime="$2"
                    shift
                    echoDebug "[${FUNCNAME[*]}] totalWaitTime==$totalWaitTime. Input == $2">&2
                else
                    echoError "[${FUNCNAME[*]}] Invalid total-wait-time=="$2".">&2
                    return 1
                fi
                ;;
            --polling-interval)
                if [ "$2" ]; then 
                    pollingInterval="$2"
                    shift
                    echoDebug "[${FUNCNAME[*]}] pollingInterval==$pollingInterval. Input == $2">&2
                else
                    echoError "[${FUNCNAME[*]}] Invalid polling-interval=="$2".">&2
                    return 1
                fi
                ;;
            --key)
                if [ "$2" ]; then 
                    key="$2"
                    shift
                    echoDebug "[${FUNCNAME[*]}] key==$key. Input == $2">&2
                else
                    echoError "[${FUNCNAME[*]}] Invalid key=="$2".">&2
                    return 1
                fi
                ;;
            --expected-value)
                if [ "$2" ]; then 
                    expectedValue="$2"
                    shift
                    echoDebug "[${FUNCNAME[*]}] expectedValue==$expectedValue. Input == $2">&2
                else
                    echoError "[${FUNCNAME[*]}] Invalid expected-value=="$2".">&2
                    return 1
                fi
                ;;
            -m|--message)
                if [ "$2" ]; then 
                    cMessage="$2"
                    shift
                    echoDebug "[${FUNCNAME[*]}] cMessage==$cMessage. Input == $2">&2
                fi
                ;;
            *)
                break
        esac
        shift
    done
    url=$1    
    # unset the first position of headers array
    unset "headers[0]"
    headers=("${headers[@]:1}")
    #
    echoDebug "[${FUNCNAME[*]}] after flags:
        url=$url

        headers=${headers[*]}
        body=$body
        method=$method
        totalWaitTime=$totalWaitTime
        pollingInterval=$pollingInterval

        key=$key
        expectedValue=$expectedValue
        cMessage=$cMessage
        ">&2
    #
    isKeyListFilled "url" "key" "expectedValue"
    checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME[*]}][isKeyListFilled] VERY BAD."
    if [[ "$?" != "0" ]]; then return 1; fi

    start_time=$(date +%s)
    while true; do
        echoDebug "[${FUNCNAME[*]}] in while loop:
            curl $url ${headers[*]} -d $body ">&2

        export TOKEN=$(gcloud auth print-access-token)

        # curl
        if [[ -z "$body" ]]; then  
            curlOutput=$(curl -s "$url" "${headers[@]}")
        else
            curlOutput=$(curl -s "$url" "${headers[@]}" -d "$body")
        fi
        # curl "$url" "${headers[*]}" -d "$body" -iv --show-error
        echoDebug "[${FUNCNAME[*]}] in while loop:
            Output:
            $curlOutput">&2

        # extract the output's key's value
        isKeyListFilledv2 "curlOutput"
        if [[ "$?" == "0" ]]; then
            keyValue=$(jq -r "$key" <<< "$curlOutput")
        else
            echoError "[${FUNCNAME[*]}] The output of the curl command is $curlOutput. Something went wrong." >&2
        fi
        # Compare the extracted key's value with the expected value
        echoDebug "[${FUNCNAME[*]}] 
            key             == $key
            value           == $keyValue
            expected value  == $expectedValue">&2

        compareTwoStrings "$keyValue" "$expectedValue" >&2
        # break logic
        if [[ "$?" == "0" ]]; then
            echoDebug "[${FUNCNAME[*]}] Key == $key has the desired value == $keyValue" >&2
            return 0
        elif [ $(($(date +%s) - start_time)) -ge "$totalWaitTime" ]; then
            echoWarning "[${FUNCNAME[*]}] Wait time exceeded. Exiting loop...">&2
            return 1
        fi
        # Wait for the next cycle
        TransitionEffect "$pollingInterval" "$cMessage"
    done
    return 0
}