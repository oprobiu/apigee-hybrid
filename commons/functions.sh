#!/bin/bash

#################### INSTALLATION FUNCTIONS ####################

enableApis() {
    # trap "echoError ${LINENO}" ERR
    # Enable the APIs at https://cloud.google.com/apigee/docs/hybrid/v1.12/precog-enableapi
    local checks=
    FLAG_ENABLE_APIS=true
    local keyList=("PROJECT_ID"
    "MAIN_SCRIPT_LOCATION"
    "RUNTIME_FLAGS_FILE_ABSOLUTE"
    "FLAG_ENABLE_APIS"
    )

    isKeyListFilledv2 "${keyList[@]}"
    # If checks will be 1, then one of the conditions above failed.
    if [[ "$?" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_ENABLE_APIS="failed"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_APIS"
        return 1
    fi
    
    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "$?" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_ENABLE_APIS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_APIS"
        return 1
    fi

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "$?" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_ENABLE_APIS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_APIS"
        return 1
    fi

    # Execution
    ## Enable APIs for GKE on 
    gcloud services enable \
        apigee.googleapis.com \
        apigeeconnect.googleapis.com \
        cloudresourcemanager.googleapis.com \
        compute.googleapis.com \
        container.googleapis.com \
        pubsub.googleapis.com --project $PROJECT_ID 2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud services enable] failed."
        FLAG_ENABLE_APIS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_APIS"
        return 1
    fi

    # [WIP] Post-Check
    gcloud services list --project $PROJECT_ID 2>&1  | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'warn' "[gcloud services list] failed."
        FLAG_ENABLE_APIS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_APIS"
        return 1
    fi

    ## Add to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_ENABLE_APIS"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_ENABLE_APIS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_APIS"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_ENABLE_APIS" "true"
    return "$?"  
}

createOrganization() {
    # Step 1.2: Create an organization as per: https://cloud.google.com/apigee/docs/hybrid/v1.12/precog-provision#no-data-residency_2
    local checks=0
    local state=
    local curlOutput=
    local keyList=("ANALYTICS_REGION" "PROJECT_ID" "RUNTIMETYPE" "RUNTIME_CACHE_FILE" "RUNTIME_FLAGS_FILE_ABSOLUTE")
    FLAG_CREATE_ORG="true"

    ## Checks variables 
    ORG_NAME="${PROJECT_ID}"
    RUNTIMETYPE="HYBRID"
    keyList+=("RUNTIMETYPE")
    isKeyListFilledv2 "${keyList[@]}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi

    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi

    ## Populate the Cache with these variables and make them persistent.
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_CACHE_FILE" "ORG_NAME" "RUNTIMETYPE" "TOKEN"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi
    # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME[*]}][updateCacheWithCurrentEnvValues]--cache-filename $RUNTIME_CACHE_FILE ORG_NAME RUNTIMETYPE"
    # if [[ "$?" != "0" ]]; then return 1; fi

    declare -g "ORG_NAME"="$PROJECT_ID"
    declare -g "RUNTIMETYPE"="$RUNTIMETYPE"

    # Create org
    curlOutput=$(curl --silent --show-error -H "Authorization: Bearer $TOKEN" -X POST -H "content-type:application/json" \
        -d '{
            "name":"'"$PROJECT_ID"'",
            "runtimeType":"'"$RUNTIMETYPE"'",
            "analyticsRegion":"'"$ANALYTICS_REGION"'"
        }' \
        "${GOOGLE_APIGEE_BASE_URL}/organizations?parent=projects/$PROJECT_ID")

    ## Get LONG_RUNNING_OPERATION_ID from the curlOutput
    LONG_RUNNING_OPERATION_ID=$(echo "${curlOutput}" | jq -r '.name' )
    LONG_RUNNING_OPERATION_ID=$(awk -F/ '{print $NF}' <<< "$LONG_RUNNING_OPERATION_ID")

    [[ ! "$LONG_RUNNING_OPERATION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && declareCacheValues "$RUNTIME_CACHE_FILE"

    ## Use the LONG_RUNNING_OPERATION_ID to curl for the state
    if [[ "$LONG_RUNNING_OPERATION_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        ## populate cache with this variable
        updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "LONG_RUNNING_OPERATION_ID"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
            FLAG_CREATE_ORG="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
            return 1
        fi
        # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME[*]}][updateCacheWithCurrentEnvValues]--cache-filename $RUNTIME_CACHE_FILE LONG_RUNNING_OPERATION_ID"
        
        # Declare 
        declare -g "LONG_RUNNING_OPERATION_ID"="$LONG_RUNNING_OPERATION_ID"
        echoDebug "LONG_RUNNING_OPERATION_ID==$LONG_RUNNING_OPERATION_ID" >&2

        ## Poll for state of the organization
        loopCurlv2 -H "Authorization: Bearer $TOKEN" -X "GET" --total-wait-time "600" --polling-interval "60" \
            --key ".metadata.state" --expected-value "FINISHED" -m "Verifying the status of the Apigee organization" \
            "${GOOGLE_APIGEE_BASE_URL}/organizations/$PROJECT_ID/operations/$LONG_RUNNING_OPERATION_ID"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'warn' "[loopCurlv2] failed."
            FLAG_CREATE_ORG="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
            return 1
        fi
        # checkChecksAndFlag -mt "ERROR" -ff "$RUNTIME_FLAGS_FILE_ABSOLUTE" \
        #     -f "FLAG_CREATE_ORG" -fv "failed" -fc "0" "$?" \
        #     "[${FUNCNAME[*]}] "
    fi 
    
    echoDebug "curl --silent --show-error -H Authorization: Bearer $TOKEN \n ${GOOGLE_APIGEE_BASE_URL}/organizations/$PROJECT_ID \n##############################################\nResult of the curl:\n$curlOutput" >&2

    curlOutput=$(getCurlStatus "${GOOGLE_APIGEE_BASE_URL}/organizations/$PROJECT_ID")
    compareTwoStrings "$curlOutput" "200"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[compareTwoStrings] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi

    ## Add to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_ORG"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_CREATE_ORG" "true"
    return "$?" 
}

createEnv() {
    # Step 1.3: Create an env as per: https://cloud.google.com/apigee/docs/hybrid/v1.12/precog-add-environment#apigee-api_1
    # $1 = project ID
    # $2 = env name
    local curlOutput=
    local projectID="$1"
    local envName="$2"
    local keyList=("TOKEN" "projectID" "envName" "RUNTIME_CACHE_FILE" "RUNTIME_FLAGS_FILE_ABSOLUTE")
    # how long to wait for curl until the curl should time out
    FLAG_CREATE_ENV="true"
    # configure default values
    [ -z "$1" ] && projectID="$PROJECT_ID"
    [ -z "$2" ] && envName="$ENV_NAME"

    echoDebug "environment==$envName"

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CREATE_ENV="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV"
        return 1
    fi
    export TOKEN

    # Export the Cached values
    isKeyListFilledv2 "${keyList[@]}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CREATE_ORG="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ORG"
        return 1
    fi

    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CREATE_ENV="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV"
        return 1
    fi

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CREATE_ENV="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV"
        return 1
    fi

    # Create environment
    curlOutput=$(curl --silent --show-error -H "Authorization: Bearer $TOKEN" -X POST \
        -H "content-type:application/json" -d '{"name": "'"$envName"'"}' \
        "${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/environments" \
        -s -o /dev/null -w "%{http_code}")
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[curl ${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/environments]"
        FLAG_CREATE_ENV="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV"
        return 1
    fi
    echoDebug "create env curl status==$curlOutput" >&2

    if [[ "$curlOutput" == "200" ]]; then 
        echoInfo "ENV==$envName in ORG==$projectID has been successfully created! Status==$curlOutput"
    elif [[ "$curlOutput" == "409" ]]; then
        echoWarning "ENV==$envName in ORG==$projectID already exists! Status==$curlOutput"
    else
        echoError "Something went wrong with creating ENV==$envName in ORG==$projectID"
        FLAG_CREATE_ENV="failed"
        updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_ENV"
        return 1
    fi

    # Loop check the state of the env above, until it displays just the name of the environment
    local start_time=$(date +%s)

    ## Poll for state of the env
    loopCurlv2 -H "Authorization: Bearer $TOKEN" \
        --key ".[] | select(. == \"$envName\")" --expected-value "$envName" -m "Checking the state of the environment" \
          "${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/environments"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[loopcurlv2]"
        FLAG_CREATE_ENV="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV"
        return 1
    fi

    ## Add to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_ENV"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_CREATE_ENV="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV"
        return 1
    fi
    ## Check if the function was completed
    compareTwoStrings "$FLAG_CREATE_ENV" "true"
    return "$?" 
}

createEnvGroup() {
    # Step 1.3: Create an env group as per: https://cloud.google.com/apigee/docs/hybrid/v1.12/precog-add-environment#apigee-api_1
    local curlOutput=
    local keyLoop=
    local projectID="$1"
    local envName="$2"
    local envGroupName="$3"
    local domain="$4"
    local curlStatus=
    local varsArray=("TOKEN" "projectID" "envName"
    "envGroupName" "domain" 
    "RUNTIME_CACHE_FILE" "RUNTIME_FLAGS_FILE_ABSOLUTE")

    FLAG_CREATE_ENV_GROUP=true
    # configure default values
    [ -z "$1" ] && projectID="$PROJECT_ID"
    [ -z "$2" ] && envName="$ENV_NAME"
    [ -z "$3" ] && envGroupName="$ENV_GROUP"
    [ -z "$4" ] && domain="$DOMAIN"

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi
    export TOKEN

    isKeyListFilledv2 "${varsArray[@]}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi
    echoDebug "projectID=$projectID\n\
        envName=$envName\n\
        envGroupName=$envGroupName\n\
        domain=$domain">&2

    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi

    ## Create environment group
    curlOutput=$(curl --silent --show-error -H "Authorization: Bearer $TOKEN" -X POST -H "content-type:application/json" \
        -d '{
        "name": "'"$envGroupName"'",
        "hostnames":["'"$domain"'"]
        }' \
        "${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/envgroups" \
        -s -o /dev/null -w "%{http_code}")

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[curl create env group]"
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV"
        return 1
    fi

    echoDebug "curl --silent --show-error -H \"Authorization: Bearer $TOKEN\" -X POST -H \"content-type:application/json\" 
        -d {
        name: $envGroupName,
        hostnames:[$domain]
        } 
        \"${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/envgroups\" 
        -s -o /dev/null -w \"%{http_code}\"\n\nstatus==$curlOutput" >&2

    if [[ "$curlOutput" =~ ^[2][0-9][0-9]$ ]]; then 
        echoInfo "[${FUNCNAME[*]}] Envgroup $envGroupName in org $projectID has been successfully created!"
    elif [[ "$curlOutput" == "409" ]]; then
        echoWarning "[${FUNCNAME[*]}] Envgroup $envGroupName in org $projectID already exists or there already exists an environment with the same hostname $domain!"
    else
        echoError "[${FUNCNAME[*]}] Something went wrong with creating ENVGROUP==$envGroupName in ORG==$projectID"
        FLAG_CREATE_ENV_GROUP="failed"
        updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi
    
    attachEnv "$projectID" "$envName" "$envGroupName"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[attachEnv "$projectID" "$envName" "$envGroupName"] failed."
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi

    keyLoop=".environmentGroups[] | select(.name == \"$envGroupName\") | .state"

    ## Poll for state of the envgroup
    loopCurlv2 -H "Authorization: Bearer $TOKEN" \
        --key "$keyLoop" --expected-value "ACTIVE" -m "Checking the state of the environment group."  \
          "${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/envgroups"

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[loopcurlv2]"
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi

    # [WIP] Visual Post-check
    curlOutput=$(curl --silent --show-error -H "Authorization: Bearer $TOKEN" \
    "${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/envgroups/$envGroupName/attachments")

    if [[ $(jq -r ".[][] | select(.environment == \"$envName\") | .environmentGroupId" <<< $curlOutput)  == "$envGroupName" ]]; then
        echoInfo "[${FUNCNAME[*]}] $envName has been attached to $envGroupName."
    else
        logMessage -t 'err' " $envName is not attached to $envGroupName."
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi

    ## Add to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_ENV_GROUP"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_CREATE_ENV_GROUP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_ENV_GROUP"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_CREATE_ENV_GROUP" "true"
    return "$?" 
}

attachEnv(){
    # ATTACHES AN EXISTING ENV TO AN EXISTING ENV GROUP
    # $1 == project name
    # $2 == env name
    # $3 == env group name
    local curlStatus=
    local projectID="$1"
    local envName="$2"
    local envGroupName="$3"
    # configure default values
    [ -z "$1" ] && projectID="$PROJECT_ID"
    [ -z "$2" ] && envName="$ENV_NAME"
    [ -z "$3" ] && envGroupName="$ENV_GROUP"

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        return 1
    fi
    export TOKEN

    ## Assign the env to the new env group
    curlStatus=$(curl --silent --show-error -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" -X POST -H "content-type:application/json" \
    -d '{
        "environment": "'"$envName"'",
    }' "${GOOGLE_APIGEE_BASE_URL}/organizations/$projectID/envgroups/$envGroupName/attachments")

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[curl assign env to env group]"
        return 1
    fi

    if [[ "$curlStatus" =~ ^[2][0-9][0-9]$ ]]; then 
        echoInfo "[${FUNCNAME[*]}] ENV==$envName was asssigned to ENVGROUP==$envGroupName in ORG==$projectID successfully!"
    elif [[ "$curlStatus" == "409" ]]  || [[ "$(jq -r '.error.status' <<< $curlStatus)" == "409" ]]; then
        echoWarning "[${FUNCNAME[*]}] ENV==$envName was already asssigned to ENVGROUP==$envGroupName in ORG==$projectID successfully!"
    else
        echoWarning "[${FUNCNAME[*]}] Something went wrong with assigning ENV==$envName to ENVGROUP==$envGroupName in ORG==$projectID. Status ==$curlStatus "
        return 1
    fi

    return 0
}

createClusterStep(){
    # Create cluster as per: https://cloud.google.com/apigee/docs/hybrid/v1.12/install-create-cluster
    local checks=
    local curlOutput=
    local keyLoop=   
    local nodepoolApigeeRuntime="apigee-runtime"
    local nodepoolApigeeData="apigee-data"
    local keysArray=("PROJECT_ID"
    "RUNTIME_FLAGS_FILE" "STORAGE_CLASS_YAML_FILE" 
    "STORAGE_CLASS_YAML" "ENV_NAME" "ENV_GROUP" 
    "DOMAIN" "CLUSTER_NAME" "CLUSTER_NUM_NODES" 
    "CLUSTER_LOCATION" "CLUSTER_VERSION" 
    "CLUSTER_MACHINE_TYPE" "CLUSTER_IMAGE_TYPE" 
    "CLUSTER_DISK_TYPE" "CLUSTER_DISK_SIZE" 
    "VPC_NETWORK")

    FLAG_CREATE_CLUSTER_STEP="true"

    isKeyListFilledv2 "${keysArray[@]}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    # Print token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    # Set project
    setGoogleProject "$PROJECT_ID"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    ## ENABLE KUBERNETES API in case it was not enabled before
    gcloud services enable container.googleapis.com  | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cloud services enable container.googleapis.com]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi
    ## Create the cluster
    createCluster \
        --runtime-cachefile "$RUNTIME_FLAGS_FILE_ABSOLUTE" \
        --cluster "$CLUSTER_NAME" \
        --project "$PROJECT_ID" \
        --region $CLUSTER_LOCATION \
        --release-channel $CLUSTER_CHANNEL \
        --num-nodes $CLUSTER_NUM_NODES \
        --machine-type "$CLUSTER_MACHINE_TYPE" \
        --image-type "$CLUSTER_IMAGE_TYPE" \
        --disk-type "$CLUSTER_DISK_TYPE" \
        --disk-size "$CLUSTER_DISK_SIZE" \
        --network "$VPC_NETWORK" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createCluster]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    ## Connect to cluster
    connectToCluster --region $CLUSTER_LOCATION --project $PROJECT_ID $CLUSTER_NAME
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[connectToCluster]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi
    ## Wait for the cluster to reconcile
    export TOKEN=$(gcloud auth print-access-token)

    loopCurlv2 -H "Authorization: Bearer $TOKEN" -X "GET" --total-wait-time "1800" --polling-interval "120" \
        --key ".status" --expected-value "RUNNING" -m "Waiting for the cluster $CLUSTER_NAME to be reconciled" \
        "https://container.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${CLUSTER_LOCATION}/clusters/${CLUSTER_NAME}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[loopCurlv2]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi
    ## Create apigee-data nodepool
    createClusterNodePool \
        --runtime-cachefile "$RUNTIME_FLAGS_FILE_ABSOLUTE" \
        --nodepool "$nodepoolApigeeData" \
        --project "$PROJECT_ID" \
        --cluster "$CLUSTER_NAME" \
        --region "$CLUSTER_LOCATION" \
        --machine-type "$CLUSTER_MACHINE_TYPE" \
        --image-type "$CLUSTER_IMAGE_TYPE" \
        --disk-type "$CLUSTER_DISK_TYPE" \
        --disk-size "$CLUSTER_DISK_SIZE" \
        --num-nodes "$CLUSTER_NUM_NODES"

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createClusterNodePool]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    ## create apigee-runtime nodepool
    createClusterNodePool \
        --runtime-cachefile "$RUNTIME_FLAGS_FILE_ABSOLUTE" \
        --nodepool "$nodepoolApigeeRuntime" \
        --project "$PROJECT_ID" \
        --cluster "$CLUSTER_NAME" \
        --region "$CLUSTER_LOCATION" \
        --machine-type "$CLUSTER_MACHINE_TYPE" \
        --image-type "$CLUSTER_IMAGE_TYPE" \
        --disk-type "$CLUSTER_DISK_TYPE" \
        --disk-size "$CLUSTER_DISK_SIZE" \
        --num-nodes "$CLUSTER_NUM_NODES"

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createClusterNodePool]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    ## Delete the default nodepool
    deleteNodePool \
        --runtime-cachefile "$RUNTIME_FLAGS_FILE_ABSOLUTE" \
        --nodepool "default-pool"\
        --project "$PROJECT_ID" \
        --cluster "$CLUSTER_NAME" \
        --region "$CLUSTER_LOCATION" 

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[deleteNodePool]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi
    ## Verify node pool list
    gcloud container node-pools list \
        --cluster=${CLUSTER_NAME} \
        --region=${CLUSTER_LOCATION} \
        --project=${PROJECT_ID} \
        --format="json" \
        --quiet

    createStorageClass \
        --runtime-cachefile "$RUNTIME_FLAGS_FILE_ABSOLUTE" \
        --project "$PROJECT_ID" \
        --cluster "$CLUSTER_NAME" \
        --region "$CLUSTER_LOCATION" \
        --storageclass-template "$STORAGE_CLASS_YAML" \
        --storageclass-file "$STORAGE_CLASS_YAML_FILE"

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[deleteNodePool]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    [[ "$ENABLE_WIF" == "true" ]] && enableWIFCluster && \
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[enableWIFCluster]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_CLUSTER_STEP"

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_CREATE_CLUSTER_STEP="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_CLUSTER_STEP"
        return 1
    fi

    ## Log the current status of the cluster
    kubectlOutput=$(kubectl get nodes >&2) && logMessage -t 'info' "[kubectl get nodes]\n${kubectlOutput}"
    kubectlOutput=$(gcloud container node-pools list --cluster "${CLUSTER_NAME}" --region "${CLUSTER_LOCATION}" >&2) \
    && logMessage -t 'info' "[gcloud container node-pools list --cluster "${CLUSTER_NAME}" --region "${CLUSTER_LOCATION}"]\n${kubectlOutput}"
    ## Check if the function was completed
    compareTwoStrings "$FLAG_CREATE_CLUSTER_STEP" "true"
    return "$?" 
}

enableWIFCluster() {
    # [WIP] 
    FLAG_ENABLE_WIF_CLUSTER="true"
    # ## Enable Workload Identity for cluster
    # gcloud container clusters update ${CLUSTER_NAME} \
    #     --workload-pool=${PROJECT_ID}.svc.id.goog \
    #     --project ${PROJECT_ID} \
    #     --region ${CLUSTER_LOCATION} \
    #     --format="json" \
    #     --quiet
    # ### check if command was successful

    ## Check if the function was completed
    echoDebug "[${FUNCNAME[*]}] FLAG_ENABLE_WIF_CLUSTER==$$FLAG_ENABLE_WIF_CLUSTER"
    compareTwoStrings "$FLAG_ENABLE_WIF_CLUSTER" "true"
    return "$?" 
}


downloadHelmCharts () {
    # Step 2.2: Downloads the Apigee Helm Charts as per https://cloud.google.com/apigee/docs/hybrid/v1.12/install-download-charts
    local checks=
    local keysArray=("MAIN_SCRIPT_LOCATION" "RUNTIME_FLAGS_FILE" 
    "RUNTIME_FLAGS_FILE_ABSOLUTE" "RUNTIME_CACHE_FILE" 
    "CHART_REPO" "CHART_VERSION" "APIGEE_HYBRID_BASE" 
    "APIGEE_HELM_CHARTS_HOME" "HELM_CHART_SUBDIRS")
    FLAG_HELM_CHARTS="true"

    # Check if variables are filled
    isKeyListFilledv2 "${keysArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_HELM_CHARTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
        return 1
    fi

    # Set project
    setGoogleProject "$PROJECT_ID"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_HELM_CHARTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
        return 1
    fi
   
    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_HELM_CHARTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
        return 1
    fi
    export TOKEN

    # Create runtime variabile
    APIGEE_HELM_CHARTS_ABSOLUTE="${MAIN_SCRIPT_LOCATION}/${APIGEE_HYBRID_BASE}/${APIGEE_HELM_CHARTS_HOME}"

    ## add the variable to the runtime cache file
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_CACHE_FILE" "APIGEE_HELM_CHARTS_ABSOLUTE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_HELM_CHARTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
        return 1
    fi

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_HELM_CHARTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
        return 1
    fi

    mkdir -p "${APIGEE_HYBRID_BASE}/${APIGEE_HELM_CHARTS_HOME}" 2>&1 | tee -a "${ABS_LOGS_FILE}"

    # Move to the helm chart directory
    cd "${APIGEE_HELM_CHARTS_ABSOLUTE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd ${APIGEE_HELM_CHARTS_ABSOLUTE}] failed."
        FLAG_HELM_CHARTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
        return 1
    fi
    # Download the repos and check each pull
    for component in "${HELM_CHART_SUBDIRS[@]}"; do
        helm pull ${CHART_REPO}/${component} --version ${CHART_VERSION} --untar  | tee -a "${ABS_LOGS_FILE}"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'warn' "[helm pull ${CHART_REPO}/${component} --version ${CHART_VERSION} --untar] Failed to pull the chart."
            FLAG_HELM_CHARTS="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
            return 1
        fi     
    done

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_HELM_CHARTS"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_HELM_CHARTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_CHARTS"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_HELM_CHARTS" "true"
    return "$?" 
}

createNamespace(){
    # Step 2.3: Create the apigee namespace as per https://cloud.google.com/apigee/docs/hybrid/v1.12/install-create-namespace
    local keysArray=("MAIN_SCRIPT_LOCATION" "RUNTIME_FLAGS_FILE" 
    "RUNTIME_FLAGS_FILE_ABSOLUTE" "APIGEE_NAMESPACE" 
    "CLUSTER_LOCATION" "PROJECT_ID" "CLUSTER_NAME" 
    "RUNTIME_CACHE_FILE" "APIGEE_HYBRID_BASE" 
    "APIGEE_HELM_CHARTS_HOME" "HELM_CHART_SUBDIRS")
    FLAG_NAMESPACE="true"

    isKeyListFilledv2 "${keysArray[@]}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_NAMESPACE="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_NAMESPACE"
        return 1
    fi

    # Set project
    setGoogleProject "$PROJECT_ID"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_NAMESPACE="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_NAMESPACE"
        return 1
    fi

    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_NAMESPACE="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_NAMESPACE"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_NAMESPACE="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_NAMESPACE"
        return 1
    fi

    ## Connect to cluster
    connectToCluster --region $CLUSTER_LOCATION --project $PROJECT_ID $CLUSTER_NAME
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[connectToCluster]"
        FLAG_NAMESPACE="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_NAMESPACE"
        return 1
    fi
    
    ## create namespace
    kubectl create namespace "$APIGEE_NAMESPACE" 2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]] && [[ $(kubectl get namespace "${APIGEE_NAMESPACE}" &> /dev/null; echo "$?") == "0" ]] ; then
        logMessage -t 'warn' "[kubectl create namespace $APIGEE_NAMESPACE] Unable to create the namespace ${APIGEE_NAMESPACE} because it already exists."
    fi

    ## visual check
    kubectl get namespace "$APIGEE_NAMESPACE" -o wide 2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[kubectl get namespace $APIGEE_NAMESPACE]"
        FLAG_NAMESPACE="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_NAMESPACE"
        return 1 
    fi

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_NAMESPACE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_NAMESPACE="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_NAMESPACE"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_NAMESPACE" "true"
    return "$?" 
}

createServiceAccount() {
    # Step 2.4: https://cloud.google.com/apigee/docs/hybrid/v1.12/install-service-accounts
    # [INFO] JUST NON-PROD. NO KUBERNETES SECRETS
    ########## Initialization ##########
    local checks=
    local output=
    local maxSA=10
    local keysArray=
    local confirmationMessage="The SA has $maxSA or more keys!\nYou can remove the keys from IAM > Service Accounts section of the GCP Console.\nIf instead you would like to delete all existing keys for this SA, then type y.\nOtherwise, you will be routed to the menu.\n[Y|n]: "
    local dirs=("$APIGEE_HELM_CHARTS_ABSOLUTE/apigee-telemetry/" "$APIGEE_HELM_CHARTS_ABSOLUTE/apigee-org/" "$APIGEE_HELM_CHARTS_ABSOLUTE/apigee-env/")
    local varsArray=("MAIN_SCRIPT_LOCATION" "RUNTIME_FLAGS_FILE" 
    "RUNTIME_FLAGS_FILE_ABSOLUTE" "PROJECT_ID" 
    "CLUSTER_LOCATION" "CLUSTER_NAME" "RUNTIME_CACHE_FILE" 
    "APIGEE_HYBRID_BASE" "APIGEE_HELM_CHARTS_HOME")
    FLAG_CREATE_SA="true"
 
    # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    # Set project
    setGoogleProject "$PROJECT_ID"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    ## Connect to cluster
    connectToCluster --region $CLUSTER_LOCATION --project $PROJECT_ID $CLUSTER_NAME
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[connectToCluster]"
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    # Create runtime variabiles
    SA_NONPROD_FILE_NAME="${PROJECT_ID}-apigee-non-prod.json"

    ## add the variable to the runtime cache file
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_CACHE_FILE" "SA_NONPROD_FILE_NAME"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    # Check if the exists
    isFileEmpty "$APIGEE_HELM_CHARTS_ABSOLUTE/apigee-operator/etc/tools/create-service-account"
    if [[ "${PIPESTATUS[0]}" == "0" ]]; then
        logMessage -t 'err' "[isFileEmpty $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-operator/etc/tools/create-service-account]\nThe service account creation tools is empty."
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    # Give the service account script the execute permission
    chmod +x "$APIGEE_HELM_CHARTS_ABSOLUTE/apigee-operator/etc/tools/create-service-account"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[chmod +x $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-operator/etc/tools/create-service-account]"
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    # STARTING THE LOOP TO CHECK FOR KEYS
    while :; do 
        # Check the number of keys associated with the non-prod service account
        output=$(gcloud iam service-accounts keys list \
            --iam-account="apigee-non-prod@$PROJECT_ID.iam.gserviceaccount.com" \
            --quiet \
            --format=json)
        
        # select for just the user managed keys
        keysArray=("$(jq -r '.[] | select(.keyType == "USER_MANAGED") | .name | split ("/") | .[-1]' <<<$output)")
        
        # check if there are more than 10 keys asssociated with the SA account
        if (( $(wc -l <<<$keysArray) >= $maxSA )); then
            printf "${confirmationMessage}" >&2
            confirmYes
            checks="$?"
            if [[ "${PIPESTATUS[0]}" != "$checks" ]]; then
                logMessage -t 'err' "[confirmYes] You chose to manually delete the SA keys."
                FLAG_CREATE_SA="false"
                updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
                return 1
            fi
        else
            break
        fi

        if (( $checks == 0)); then
            keysArray=("$(jq -r '.[] | select(.keyType == "USER_MANAGED") | .name | split ("/") | .[-1]' <<<$output)")
            keysArray=($keysArray)
            deleteSAKeys "apigee-non-prod" "$PROJECT_ID" "${keysArray[@]}"
            # checks=$?
        # elif [[ "$?" == "1" ]]; then return 1; 
        fi

    done

    # create the SA
    yes | $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-operator/etc/tools/create-service-account \
        --env non-prod \
        --dir $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-datastore
    # checks=$?
    if [[ "${PIPESTATUS[1]}" != "0" ]]; then
        logMessage -t 'err' "[$APIGEE_HELM_CHARTS_ABSOLUTE/apigee-operator/etc/tools/create-service-account --env non-prod]"
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    checkFileName $(find $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-datastore/ -iname "$PROJECT_ID-apigee-non-prod.json") "$PROJECT_ID-apigee-non-prod.json"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[checkFileName]"
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi
    ## Copy the SA to the appropriate dirs
    for direct in "${dirs[@]}"; do
        cp "${APIGEE_HELM_CHARTS_ABSOLUTE}/apigee-datastore/${SA_NONPROD_FILE_NAME}" "${direct}"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[cp ${APIGEE_HELM_CHARTS_ABSOLUTE}/apigee-datastore/${SA_NONPROD_FILE_NAME} ${direct}]"
            FLAG_CREATE_SA="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
            return 1
        fi
    done 

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_SA"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_CREATE_SA="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_SA"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_CREATE_SA" "true"
    return "$?" 
}

createTLSCerts(){
    # Step 2.5: https://cloud.google.com/apigee/docs/hybrid/v1.12/install-create-tls-certificates    
    local checks=
    local varsArray=("APIGEE_HELM_CHARTS_ABSOLUTE" "MAIN_SCRIPT_LOCATION" 
    "APIGEE_HYBRID_BASE" "APIGEE_HELM_CHARTS_HOME" 
    "DOMAIN" "ENV_GROUP" "PROJECT_ID" 
    "PROD_TYPE" "RUNTIME_FLAGS_FILE_ABSOLUTE")
    FLAG_CREATE_TLS_CERTS="true"

    # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi

    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi

    # Create the cets directory
    mkdir $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-virtualhost/certs/ 2>&1 | tee -a "${ABS_LOGS_FILE}"

    # Create the certificate and key
    openssl req  -nodes -new -x509 -keyout $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-virtualhost/certs/keystore_$ENV_GROUP.key -out \
    $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-virtualhost/certs/keystore_$ENV_GROUP.pem \
        -subj '/CN='$DOMAIN'' \
        -days 3650 2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[openssl req  -nodes -new -x509 -keyout $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-virtualhost/certs/keystore_$ENV_GROUP.key -out $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-virtualhost/certs/keystore_$ENV_GROUP.pem -subj '/CN='$DOMAIN'' -days 3650] failed."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi

    # Check if the cert and key exist
    [ -s "${APIGEE_HELM_CHARTS_ABSOLUTE}/apigee-virtualhost/certs/keystore_${ENV_GROUP}.key" ] && \
    [ -s "${APIGEE_HELM_CHARTS_ABSOLUTE}/apigee-virtualhost/certs/keystore_${ENV_GROUP}.pem" ]
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isFileEmpty $APIGEE_HELM_CHARTS_ABSOLUTE/apigee-virtualhost/certs/keystore_$ENV_GROUP.key or pem] missing key or pem."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi

    declare -g "PATH_TO_CERT_FILE"="certs/keystore_${ENV_GROUP}.pem"
    declare -g "PATH_TO_KEY_FILE"="certs/keystore_${ENV_GROUP}.key"
    
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "PATH_TO_CERT_FILE" "PATH_TO_KEY_FILE" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi

    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_TLS_CERTS"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_CREATE_TLS_CERTS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_TLS_CERTS"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_CREATE_TLS_CERTS" "true"
    return "$?" 
}

createOverrides(){
    # Step 2.6: https://cloud.google.com/apigee/docs/hybrid/v1.12/install-create-overrides
    # Creates the non-prod overrides file without workload identity
    local overridesFile=                        
    local overridesYamlTemplate=
    local pattern=
    local type=
    local checks=
    local overridesVariables=
    local version=
    # local pattern='\$[A-Z_]*'
    ### FLAG HANDLING ###
    while :; do
        case $1 in
            -h|-\?|--help)
                echo " #[HELP OPTIONS][WIP]"
                exit
                ;;
            --filename|-f) 
                # ensure that value is specified
                # path/to/overrides.yaml file
                if [ "${2}" ]; then
                    overridesFile=$2
                    shift
                else
                    echo "[${FUNCNAME[*]}] '--filename|-f' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --template|-t)               
                # ensure that it is specified
                if [ "${2}" ]; then
                    overridesYamlTemplate=$2
                    shift
                else
                    echo "[${FUNCNAME[*]}] '--template|-t' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --pattern|-p) 
                # ensure that value is specified
                if [ "${2}" ]; then
                    pattern=$2
                    shift
                else
                    echo "[${FUNCNAME[*]}] '--pattern|-p' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            # --type) 
            #     # ensure that value is specified
            #     if [ "${2}" ]; then
            #         type=$2
            #         shift
            #     else
            #         echo "[${FUNCNAME[*]}] '--type' requires a non-empty option argument" >&2
            #         return 1
            #     fi
            #     ;;
            *)
                break
        esac
        shift
    done

    local varsArray=("MAIN_SCRIPT_LOCATION" "RUNTIME_FLAGS_FILE" 
    "RUNTIME_FLAGS_FILE_ABSOLUTE" "PROJECT_ID" "CLUSTER_LOCATION" 
    "CLUSTER_NAME" "RUNTIME_CACHE_FILE" "APIGEE_HYBRID_BASE" 
    "APIGEE_HELM_CHARTS_HOME" "overridesFile" 
    "overridesYamlTemplate" "pattern")
    export TOKEN=$(gcloud auth print-access-token)
    FLAG_CREATE_OVERRIDES="true"
 
     # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi

    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi

    # Create the overrides.yaml file/overwrites it.
    createAndPopulateFile "$overridesFile" "$overridesYamlTemplate"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createAndPopulateFile] Unable to create and/or populate the '$overridesFile'."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi

    # based on the overrides yaml template get the necessary variables 
    overridesVariables=("$(simpleGrepSEdExtrF2V ${pattern} ${overridesFile})")
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[overridesVariables=(.....)]"
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi

    # sort and remove duplicates
    readarray -t overridesVariables < <(printf '%s\n' "${overridesVariables[@]}" | sort | uniq) 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[readarray -t overridesVariables]"
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi
    
    # Check if the variables are filled
    isKeyListFilledv2 "${overridesVariables[@]}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] Verification of the necessary variables to fill the overrides.yaml file failed, due to missing/bad values for one or more variables."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi
    
    # replaceArrayOfValuesInFIle "${overridesFile})" '\$[A-Z_]*' 
    replaceKeysWithTheirValuesInFile "$overridesFile" "${overridesVariables[@]}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[replaceKeysWithTheirValuesInFile] failed."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CREATE_OVERRIDES"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_CREATE_OVERRIDES="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CREATE_OVERRIDES"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_CREATE_SA" "true"
    return "$?" 
}

enableSynchronizer(){
    # Step 2.7: Enable Synchronizer access https://cloud.google.com/apigee/docs/hybrid/v1.12/install-enable-synchronizer-access
    local apigeeSASync=
    local apigeeSARuntime=
    local curlStatusCode=
    local analyticLRO=
    local varsArray=("APIGEE_HELM_CHARTS_ABSOLUTE" "MAIN_SCRIPT_LOCATION" 
    "APIGEE_HYBRID_BASE" "APIGEE_HELM_CHARTS_HOME" 
    "DOMAIN" "ENV_GROUP" "PROJECT_ID" 
    "PROD_TYPE" "ADMIN_EMAIL" "RUNTIME_FLAGS_FILE_ABSOLUTE")
    FLAG_ENABLE_SYNCHRONIZER="true"

    # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi


    ## choose type
    apigeeSASync="apigee-non-prod"
    apigeeSARuntime="${apigeeSASync}"

    [[ "$PROD_TYPE" == "PROD" ]] && apigeeSASync="apigee-synchronizer" && apigeeSARuntime='apigee-runtime'

    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi

    # Add admin role
    gcloud projects add-iam-policy-binding ${PROJECT_ID} \
        --member user:${ADMIN_EMAIL} \
        --role roles/apigee.admin \
        2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[ gcloud projects add-iam-policy-binding ${PROJECT_ID}] Could not add-iam-policy-binding for $ADMIN_EMAIL!"
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi

    gcloud projects get-iam-policy ${PROJECT_ID}  \
        --flatten="bindings[].members" \
        --format='table(bindings.role)' \
        --filter="bindings.members:${ADMIN_EMAIL}" \
        2>&1| tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[ gcloud projects get-iam-policy-binding ${PROJECT_ID}] Could not get-iam-policy-binding for $ADMIN_EMAIL!"
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi

    gcloud iam service-accounts list --project "${PROJECT_ID}" --filter "$apigeeSASync" 2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud iam service-accounts list --project ${PROJECT_ID} --filter $apigeeSASync]"
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi



    # Call the setSyncAuthorization API to enable the required permissions for Synchronizer
    if [[ "${CHART_VERSION%.*}" < "1.14" ]]; then
        curlStatusCode=$(curl -X POST -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type:application/json" \
            "${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}:setSyncAuthorization" \
            -d '{"identities":["'"serviceAccount:${apigeeSASync}@${PROJECT_ID}.iam.gserviceaccount.com"'"]}' \
            -i -w "%{http_code}" \
            -s -o /dev/null
            )

        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[curl -X POST ${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}:setSyncAuthorization] failed to curl."
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi

        curlStatusCode=$(curl -X GET -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type:application/json" \
            "${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}:getSyncAuthorization" \
            -i -w "%{http_code}" \
            -s -o /dev/null)

        compareTwoStrings "$curlStatusCode" "200"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[curl -X POST ${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}:getSyncAuthorization] failed to curl."
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi  

    else
        # Enable Control Plane access
        ## Enable sync access 
        curlStatusCode=$(curl -X PATCH -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type:application/json" \
        "${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}/controlPlaneAccess?update_mask=synchronizer_identities" \
        -d "{\"synchronizer_identities\": [\"serviceAccount:${apigeeSASync}@${PROJECT_ID}.iam.gserviceaccount.com\"]}" \
        -s
        )

        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[curl -X POST ${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}/controlPlaneAccess?update_mask=synchronizer_identities] failed to curl. Output: \n${curlStatusCode}"
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi

        ####
        analyticLRO=$(jq -r '.name' <<< $curlStatusCode | awk -F '/' '{print $NF}' )
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "Failed to get the LRO ID for the Synchronizer Access process."
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi

        ### Poll for state of the operation
        loopCurlv2 -H "Authorization: Bearer $TOKEN" -X "GET" --total-wait-time "60" --polling-interval "10" \
            --key ".metadata.state" --expected-value "FINISHED" -m "Verifying the status of the SA ${apigeeSARuntime} synchronizer access." \
            "${GOOGLE_APIGEE_BASE_URL}/organizations/$PROJECT_ID/operations/$analyticLRO"

        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'warn' "[loopCurlv2] failed to conclude whether the LRO ${analyticLRO} was completed successfully or not."
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi

        ### Visual verification.
        curl -X GET -H "Authorization: Bearer $TOKEN" \
            -H "Content-Type:application/json" \
            "${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}/controlPlaneAccess" \
            -s

        # compareTwoStrings "$curlStatusCode" "200"
        # if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        #     logMessage -t 'err' "[curl -X POST ${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}/controlPlaneAccess] failed to curl."
        #     FLAG_ENABLE_SYNCHRONIZER="false"
        #     updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        #     return 1
        # fi  

        ## Enable analytics publisher access
        curlStatusCode=$(curl -X PATCH -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type:application/json" \
        "${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}/controlPlaneAccess?update_mask=analytics_publisher_identities" \
        -d "{\"analytics_publisher_identities\": [\"serviceAccount:${apigeeSARuntime}@${PROJECT_ID}.iam.gserviceaccount.com\"]}" \
        -s
        )

        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[curl -X POST ${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}/controlPlaneAccess?update_mask=analytics_publisher_identities] failed to curl to enable analytics publisher access."
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi

        analyticLRO=$(jq -r '.name' <<< $curlStatusCode | awk -F '/' '{print $NF}' )
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "Failed to get the LRO ID for the Analytics Publisher Access process."
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi

        ### Poll for state of the operation
        loopCurlv2 -H "Authorization: Bearer $TOKEN" -X "GET" --total-wait-time "60" --polling-interval "10" \
            --key ".metadata.state" --expected-value "FINISHED" -m "Verifying the status of the SA ${apigeeSARuntime} access to publish analytics." \
            "${GOOGLE_APIGEE_BASE_URL}/organizations/$PROJECT_ID/operations/$analyticLRO"

        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'warn' "[loopCurlv2] failed to conclude whether the LRO ${analyticLRO} was completed successfully or not."
            FLAG_ENABLE_SYNCHRONIZER="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
            return 1
        fi
        
    fi

    logMessage -t 'info' "API call to Control Plane made for version ${CHART_VERSION}."

    curl -X GET -H "Authorization: Bearer $TOKEN" \
        "${GOOGLE_APIGEE_BASE_URL}/organizations/${PROJECT_ID}/controlPlaneAccess" \
        -s

    #
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_ENABLE_SYNCHRONIZER"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_ENABLE_SYNCHRONIZER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_ENABLE_SYNCHRONIZER"
        return 1
    fi  

    ## Check if the function was completed
    compareTwoStrings "$FLAG_ENABLE_SYNCHRONIZER" "true"
    return "$?" 
}

installCertManager(){
    # Step 2.8: install cert manager https://cloud.google.com/apigee/docs/hybrid/v1.12/install-cert-manager
    local varsArray=("CERT_MANAGER_RELEASE" "APIGEE_HELM_CHARTS_ABSOLUTE" 
    "MAIN_SCRIPT_LOCATION" "APIGEE_HYBRID_BASE" 
    "APIGEE_HELM_CHARTS_HOME" "DOMAIN" 
    "ENV_GROUP" "PROJECT_ID" 
    "PROD_TYPE" "ADMIN_EMAIL"
    "RUNTIME_FLAGS_FILE_ABSOLUTE")
    local certManagerRepo="https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_RELEASE}/cert-manager.yaml"

    FLAG_INSTALL_CERT_MANANGER="true"

    # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi

    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi

    ## Connect to cluster
    connectToCluster --region $CLUSTER_LOCATION --project $PROJECT_ID $CLUSTER_NAME
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[connectToCluster]"
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi

    # Download and apply the cert manager yaml
    kubectl apply -f "$certManagerRepo" 2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[kubectl apply -f $certManagerRepo]"
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi

    # Visual CHECK
    kubectl get all -n cert-manager -o wide 2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[kubectl get all -n cert-manager -o wide]"
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_INSTALL_CERT_MANANGER"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_INSTALL_CERT_MANANGER="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CERT_MANANGER"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_INSTALL_CERT_MANANGER" "true"
    return "$?" 
}

installCRDs(){
    # Step 2.9 : https://cloud.google.com/apigee/docs/hybrid/v1.12/install-crds
    local varsArray=("APIGEE_HELM_CHARTS_ABSOLUTE" "MAIN_SCRIPT_LOCATION" 
    "APIGEE_HYBRID_BASE" "APIGEE_HELM_CHARTS_HOME" 
    "DOMAIN" "ENV_GROUP" "PROJECT_ID" 
    "PROD_TYPE" "ADMIN_EMAIL" 
    "RUNTIME_FLAGS_FILE_ABSOLUTE")
    FLAG_INSTALL_CRDS="true"
    # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi

    # Set project
    setGoogleProject "$PROJECT_ID"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$APIGEE_HELM_CHARTS_ABSOLUTE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi

    ## Connect to cluster
    connectToCluster --region $CLUSTER_LOCATION --project $PROJECT_ID $CLUSTER_NAME
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[connectToCluster]"
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi

    ## Do the dry run
    kubectl apply -k apigee-operator/etc/crds/default/ \
        --server-side \
        --force-conflicts \
        --validate=false \
        --dry-run=server \
        2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[kubectl apply -k apigee-operator/etc/crds/default/ --dry-run=server]"
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi

    ## installing 
    kubectl apply -k  apigee-operator/etc/crds/default/ \
        --server-side \
        --force-conflicts \
        --validate=false \
        2>&1 | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[kubectl apply -k apigee-operator/etc/crds/default/]"
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi

    ## Visual validation.
    kubectl get crds 2>&1 | tee -a "${ABS_LOGS_FILE}" | grep apigee

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_INSTALL_CRDS"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_INSTALL_CRDS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_INSTALL_CRDS"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_INSTALL_CRDS" "true"
    return "$?" 
}

checkClusterReadiness(){
    # 2.10: Check cluster readiness https://cloud.google.com/apigee/docs/hybrid/v1.12/install-check-cluster
    local output=
    local start_time=
    local varsArray=("APIGEE_HELM_CHARTS_ABSOLUTE" "MAIN_SCRIPT_LOCATION" 
    "APIGEE_HYBRID_BASE" "APIGEE_HELM_CHARTS_HOME"
    "DOMAIN" "ENV_GROUP" "PROJECT_ID"
    "PROD_TYPE" "ADMIN_EMAIL"
    "CLUSTER_LOCATION" "CLUSTER_NAME"
    "RUNTIME_FLAGS_FILE_ABSOLUTE" "CLUSTER_CHECK_YAML")
    local maxWaitTime="200"
    local crcyamlPath="${APIGEE_HELM_CHARTS_ABSOLUTE}/cluster-check/apigee-k8s-cluster-ready-check.yaml"
    FLAG_CHECK_CLUSTER_READINESS="true"

    # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        return 1
    fi

    # Set project
    setGoogleProject "$PROJECT_ID"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        return 1
    fi
    export TOKEN

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        return 1
    fi

    ## Connect to cluster
    connectToCluster --region $CLUSTER_LOCATION --project $PROJECT_ID $CLUSTER_NAME
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[connectToCluster]"
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        return 1
    fi

    ## Create cluster check file 
    # mkdir $APIGEE_HELM_CHARTS_ABSOLUTE/cluster-check
    createAndPopulateFile "${crcyamlPath}" "${CLUSTER_CHECK_YAML}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'warn' "[createAndPopulateFile ${crcyamlPath} ${CLUSTER_CHECK_YAML}]"
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        rm -rfv "${crcyamlPath}" 2>&1 | tee -a "${ABS_LOGS_FILE}"
        return 1
    fi

    ## apply the cluster check file
    kubectl apply -f "$APIGEE_HELM_CHARTS_ABSOLUTE/cluster-check/apigee-k8s-cluster-ready-check.yaml"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[ kubectl apply -f "$APIGEE_HELM_CHARTS_ABSOLUTE/cluster-check/apigee-k8s-cluster-ready-check.yaml"]"
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        rm -rfv "${crcyamlPath}" 2>&1 | tee -a "${ABS_LOGS_FILE}"
        return 1
    fi
    
    ## check the status
    start_time=$(date +%s)
    while true; do 
        TransitionEffect "30"  "Checking cluster readiness..."
        kubectl get jobs apigee-k8s-cluster-ready-check 2>&1 | tee -a "${ABS_LOGS_FILE}"
        output=$(kubectl get jobs apigee-k8s-cluster-ready-check -o json | jq ".status.succeeded")
        compareTwoStrings "$output" "1"
        if [[ "$?" == "0" ]]; then
            echoInfo "[kubectl get jobs apigee-k8s-cluster-ready-check] cluster ready job completed!" >&2
            break
        elif (( $(($(date +%s) - start_time)) >= "$maxWaitTime" )); then
            logMessage -t 'err' "[kubectl get jobs apigee-k8s-cluster-ready-check] Wait time exceeded. Exiting loop..."
            FLAG_CHECK_CLUSTER_READINESS="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
            break  
        fi

    done
    
    kubectl delete -f "$APIGEE_HELM_CHARTS_ABSOLUTE/cluster-check/apigee-k8s-cluster-ready-check.yaml" 2>&1 | tee -a "${ABS_LOGS_FILE}"
    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_CHECK_CLUSTER_READINESS"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_CHECK_CLUSTER_READINESS="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_CHECK_CLUSTER_READINESS"
        rm -rfv "${crcyamlPath}" 2>&1 | tee -a "${ABS_LOGS_FILE}"
        return 1
    fi
    rm -rfv "${crcyamlPath}" 2>&1 | tee -a "${ABS_LOGS_FILE}"
    ## Check if the function was completed
    compareTwoStrings "$FLAG_CHECK_CLUSTER_READINESS" "true"
    return "$?" 
}

installApigeeHybridHelm(){
    # Step 2.11: Install apigee hybrid componets with helm https://cloud.google.com/apigee/docs/hybrid/v1.12/install-helm-charts
    local helmOutput=
    local kubectlOutput=
    local varsArray=("APIGEE_HELM_CHARTS_ABSOLUTE"
    "APIGEE_NAMESPACE" 
    "MAIN_SCRIPT_LOCATION"
    "APIGEE_HYBRID_BASE"
    "APIGEE_HELM_CHARTS_HOME" "DOMAIN"
    "ENV_GROUP" "PROJECT_ID" "PROD_TYPE"
    "ADMIN_EMAIL" "CLUSTER_LOCATION"
    "CLUSTER_NAME" "RUNTIME_FLAGS_FILE_ABSOLUTE"
    "CLUSTER_CHECK_YAML" "OVERRIDES_FILE_NAME"
    "INGRESS_NAME" "ENV_GROUP" "ENV_NAME")
    local operatorNamespace="$APIGEE_NAMESPACE"

    FLAG_HELM_INSTALL="true"

    # Check if variables are filled
    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    # Set project
    setGoogleProject $PROJECT_ID
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[setGoogleProject] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    # Set location
    cd "$APIGEE_HELM_CHARTS_ABSOLUTE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[cd $MAIN_SCRIPT_LOCATION] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi
    
    ## Connect to cluster
    connectToCluster --region $CLUSTER_LOCATION --project $PROJECT_ID $CLUSTER_NAME
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[connectToCluster]"
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    ## Create token
    TOKEN=$(gcloud auth print-access-token)
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[gcloud auth print-access-token] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi
    export TOKEN

    if [[ "${CHART_VERSION%.*}" < "1.13" ]]; then
        operatorNamespace='apigee-system'
    fi
    logMessage -t 'info' "Operator namespace is '$operatorNamespace'."
    
    ## Wait for the cluster to reconcile
    loopCurlv2 -H "Authorization: Bearer $TOKEN" -X "GET" --total-wait-time "360" --polling-interval "120" \
        --key ".status" --expected-value "RUNNING" -m "Waiting for the cluster $CLUSTER_NAME to be reconciled"  \
        "https://container.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${CLUSTER_LOCATION}/clusters/${CLUSTER_NAME}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'warn' "[loopCurlv2 https://container.googleapis.com/v1beta1/projects/${PROJECT_ID}/locations/${CLUSTER_LOCATION}/clusters/${CLUSTER_NAME}] The cluster may not be ready yet."
    fi

    ##### OPERATOR ######
    helmUpgradeOperator "$OVERRIDES_FILE_NAME" "$operatorNamespace"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeOperator $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    ##### DATASTORE ######
    helmUpgradeDatastore "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeDatastore $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    ##### TELEMETRY ######
    helmUpgradeTelemetry "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeDatastore $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    ##### REDIS ######
    helmUpgradeRedis "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeRedis $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi
    
    ##### INGRESS MANAGER #####
    helmUpgradeIngressManager "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeIngressManager $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    ##### ORG #####
    helmUpgradeOrg "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE" "$PROJECT_ID" "$INGRESS_NAME"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeOrg $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE $PROJECT_ID] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    ##### ENVIRONMENT #####
    helmUpgradeEnv "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE" "$ENV_NAME"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeEnv $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE $ENV_NAME] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi
    
    ##### ENV GROUP #####
    helmUpgradeEnvGroup "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE" "$ENV_GROUP"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helmUpgradeEnvGroup $OVERRIDES_FILE_NAME $APIGEE_NAMESPACE $ENV_GROUP] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_HELM_INSTALL"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
        FLAG_HELM_INSTALL="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
        return 1
    fi
   
    ## Get the apigee load balancer IP.
    compareTwoStrings "$LOAD_BALANCER_IP" ""
    if [[ "$?" == "0" ]]; then
        local lbip=$(getApigeeIngressGatewayIP "$INGRESS_NAME")  
        declare -g "LOAD_BALANCER_IP"="${lbip}"
        ## Add value to cache to cache
        updateCacheWithCurrentEnvValues --cache-filename "${MAIN_SCRIPT_LOCATION}/${RUNTIME_CACHE_FILE}" "LOAD_BALANCER_IP"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[updateCacheWithCurrentEnvValues] failed."
            FLAG_HELM_INSTALL="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_HELM_INSTALL"
            return 1
        fi
    fi
    ## Check if the function was completed
    compareTwoStrings "$FLAG_HELM_INSTALL" "true"
    return "$?" 
}

configureWIF(){
    return 0
}

exposeApigeeIngressGateway(){
    # Step 3.1: https://cloud.google.com/apigee/docs/hybrid/v1.12/install-expose-apigee-ingress
    local varsArray=("APIGEE_HELM_CHARTS_ABSOLUTE" "MAIN_SCRIPT_LOCATION" 
    "APIGEE_HYBRID_BASE" "APIGEE_HELM_CHARTS_HOME" 
    "DOMAIN" "ENV_GROUP" "PROJECT_ID" 
    "PROD_TYPE" "ADMIN_EMAIL" 
    "CLUSTER_LOCATION" 
    "CLUSTER_NAME" "RUNTIME_FLAGS_FILE_ABSOLUTE" 
    "CLUSTER_CHECK_YAML" "OVERRIDES_FILE_NAME" 
    "INGRESS_NAME" "ENV_GROUP" 
    "ENV_NAME" "EXPOSE_INGRESS_YAML"
    "APIGEE_NAMESPACE")
    local curlOutput=
    local pattern='.items[].status.loadBalancer.ingress[].ip'
    local templateVariables=
    local lbIP=
    local ingressVariables=
    FLAG_EXPOSE_INGRESS_GATEWAY="true"

    cd "$MAIN_SCRIPT_LOCATION"

    if [[ "${EXPOSE_INGRESS_GATEWAY^^}" == "NONPROD" ]]; then
        ## modify the overrides yaml file to have LB ingress
        replaceSedRangeYaml "ingressGateways" "virtualhosts" "svcType" "ClusterIP" "LoadBalancer" "${APIGEE_HELM_CHARTS_ABSOLUTE}/${OVERRIDES_FILE_NAME}"
        if [[ "$?" != "0" ]]; then return 1; fi

        ## apply with helm the changes
        cd "${APIGEE_HELM_CHARTS_ABSOLUTE}"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[cd ${APIGEE_HELM_CHARTS_ABSOLUTE}] failed."
            FLAG_EXPOSE_INGRESS_GATEWAY="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_EXPOSE_INGRESS_GATEWAY"
            return 1
        fi

        helmUpgradeOrg "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE" "$PROJECT_ID" "$INGRESS_NAME" > /dev/null 
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[helmUpgradeOrg] failed to ugprade org for '$EXPOSE_INGRESS_GATEWAY'."
            FLAG_EXPOSE_INGRESS_GATEWAY="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_EXPOSE_INGRESS_GATEWAY"
            return 1
        fi

        # get the ingress ip.
        lbip=$(getApigeeIngressGatewayIP "$INGRESS_NAME")
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[getApigeeIngressGatewayIP] Could not get the IP==$lbip for ingress==$INGRESS_NAME."
            FLAG_EXPOSE_INGRESS_GATEWAY="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_EXPOSE_INGRESS_GATEWAY"
            return 1
        fi


    elif [[ "${EXPOSE_INGRESS_GATEWAY^^}" == "PROD" ]]; then
        ## create the new ingress service file
        createAndPopulateFile "$EXPOSE_INGRESS_YAML_FILE" "$EXPOSE_INGRESS_YAML"
        if [[ "$?" != "0" ]]; then return 1; fi

        ## based on the overrides yaml template get the necessary variables 
        pattern='\$[A-Z_]*'
        ingressVariables=("$(simpleGrepSEdExtrF2V ${pattern} ${EXPOSE_INGRESS_YAML_FILE})")
        if [[ "$?" != "0" ]]; then return 1; fi

        ## sort and remove duplicates
        readarray -t ingressVariables < <(printf '%s\n' "${ingressVariables[@]}" | sort | uniq) 
        if [[ "$?" != "0" ]]; then return 1; fi
        
        ## Check if the variables are filled
        isKeyListFilledv2 "${ingressVariables[@]}"
        if [[ "$?" != "0" ]]; then return 1; fi
        
        ##
        replaceKeysWithTheirValuesInFile "$EXPOSE_INGRESS_YAML_FILE" "${ingressVariables[@]}"
        if [[ "$?" != "0" ]]; then return 1; fi

        ## Apply the service configuration
        kubectl apply -f "$EXPOSE_INGRESS_YAML_FILE"
        if [[ "$?" != "0" ]]; then return 1; fi

        ## modify the overrides.yaml file
        replaceSedRangeYaml "ingressGateways" "virtualhosts" "svcType" "LoadBalancer" "ClusterIP" "${APIGEE_HELM_CHARTS_ABSOLUTE}/${OVERRIDES_FILE_NAME}"
        if [[ "$?" != "0" ]]; then return 1; fi

        ## apply with helm the changes
        cd "${APIGEE_HELM_CHARTS_ABSOLUTE}"

        helmUpgradeOrg "$OVERRIDES_FILE_NAME" "$APIGEE_NAMESPACE" "$PROJECT_ID" "$INGRESS_NAME"
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[helmUpgradeOrg] failed to ugprade org for '$EXPOSE_INGRESS_GATEWAY'."
            FLAG_EXPOSE_INGRESS_GATEWAY="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_EXPOSE_INGRESS_GATEWAY"
            return 1
        fi

        ## Get the IP of the new custom ingress
        lbip=$(kubectl get svc -n apigee "$INGRESS_NAME" -o json | jq -r ".status.loadBalancer.ingress[].ip")
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[helmUpgradeOrg] failed to ugprade org for '$EXPOSE_INGRESS_GATEWAY'."
            FLAG_EXPOSE_INGRESS_GATEWAY="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_EXPOSE_INGRESS_GATEWAY"
            return 1
        fi
        # ## check new ingress health

        # checkApigeeIngressHealth "$DOMAIN" "$lbip"
        # [[ "$?" != "0" ]] &&  echoError "The ingress $INGRESS_NAME is not healthy: domain==${DOMAIN} && LB_IP==${lbip} " && return 1 
    fi

    ## check the default ingress $INGRESS_NAME's health.
    checkApigeeIngressHealth "$DOMAIN" "$lbip"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[checkApigeeIngressHealth] The ingress is not healthy: domain==${DOMAIN} && LB_IP==${lbip}"
        FLAG_EXPOSE_INGRESS_GATEWAY="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_EXPOSE_INGRESS_GATEWAY"
        return 1
    fi

    updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_EXPOSE_INGRESS_GATEWAY"
    return "$?"
}

################# END OF INSTALLATION FUNCTIONS ################
################################################################

#################        WHIPTAIL MENUS        #################
wmhm(){
    ## whiptail manual main menu
    local message="Choose an option:"
    local options=("${WHIPTAIL_MANUAL_MENU_OPTIONS[@]}")
    local menuTitle="Apigee Hybrid Manual Installation Menu"
    local userChoice=

    while true; do
        # userInput=
        ## add to env the current values for the flags
        declareCacheValues "$RUNTIME_FLAGS_FILE_ABSOLUTE"

        ## declare user variables
        declareCacheValues "$CACHED_VALUES_FILE_ABSOLUTE"

        ## flush the user input
        flushInput
        # echo "whiptail options=='${WHIPTAIL_MANUAL_MENU_OPTIONS[@]}'" 
        ## start menu
        userChoice=$(whiptailMenu --title "${menuTitle}" \
            --message "${message}" \
            --options "${options[@]}")
        [[ "$?" != '0' ]] && return 1
        case "$userChoice" in 
            "1")
                # Change varibles
                # menuUserVariables
                whiptailUserVars "Modify the following variables" "Select the variable to modify"
                continue
                ;;
            "2")
                # Step 1.1: Enable APIs option
                enableApis
                continue
                ;;
            "3")
                # Step 1.2: Create an organization
                createOrganization
                continue
                ;;
            "4")
                # Step 1.3: Create an env
                createEnv
                continue
                ;;
            "5")
                 # Step 1.3: Create an env group 
                createEnvGroup
                continue
                ;;
            "6")
                 # Step 2.1: Create cluster 
                createClusterStep
                continue
                ;;
            "7")
                 # Step 2.2: Download Apigee Helm Charts 
                downloadHelmCharts
                continue
                ;;
            "8")
                 # Step 2.3: Create the Apigee Namespace 
                createNamespace
                continue
                ;;
            "9")
                 # Step 2.4: Create Service Accounts 
                createServiceAccount
                continue
                ;;
            "10")
                 # Step 2.5: Create TLS certs
                createTLSCerts
                continue
                ;;
            "11")
                # Step 2.6: Create the Overrides
                version=$(handleVersions -r "${AVAILABLE_VERSIONS[@]}" \
                -v "${CHART_VERSION}" \
                -s "${OVERRIDES_YAML_NON_PROD_TEMPLATE_VERSIONS[@]}" 2> /dev/null)
                createOverrides --filename "${APIGEE_HELM_CHARTS_ABSOLUTE}/${OVERRIDES_FILE_NAME}" \
                --template "${!version}" \
                --pattern '\$[A-Z_]*'
                continue
                ;;
            "12")
                 # Step 2.7: Enable Synchronizer access
                enableSynchronizer
                continue
                ;;
            "13")
                # Step 2.8: install cert manager 
                installCertManager
                continue
                ;;
            "14")
                # 2.9: Install Apigee Hybrid CRDs
                installCRDs
                continue
                ;;
            "15")
                # 2.10: Check cluster readiness
                checkClusterReadiness
                continue
                ;;
            "16")
                # 2.11: Install Apigee hybrid Using Helm
                installApigeeHybridHelm
                continue
                ;;
            "17")
                # 2.12: [WIP](Optional) Configure Workload Identity
                configureWIF
                continue
                ;;
            "18")
                # 3.1: Expose Apigee ingress gateway
                exposeApigeeIngressGateway
                continue
                ;;
            *) 
                break
                ;;
        esac
        clear
    done

    return 0

}

################################################################
#################        MENU FUNCTIONS        #################
manualHybridMenu() {
    # The menu for manual installation
    local message="Choose an option by typing a number: "
    local options=("${MANUAL_MENU_OPTIONS[@]}" "Quit")
    local opt=
    local userInput=
    local coloredOptions=
    local key=
    local version=

    ## get options
    key='.[] | .[] | select(.installation == "all" or .installation == "manual") | .name'
    ##
    while true; do
        userInput=
        ## add to env the current values for the flags
        declareCacheValues "$RUNTIME_FLAGS_FILE_ABSOLUTE"

        ## declare user variables
        declareCacheValues "$CACHED_VALUES_FILE_ABSOLUTE"

        ## color the strings
        mapfile -t coloredOptions < <(colorArrayv2 "${MENU_OPTIONS_JSON}" ".[\"Manual Menu Options\"][].name" ".[][]" ".name" ".flag")

        coloredOptions+=("Quit")
        
        ## Display the menu options
        displayMenuOptions "" "" "${coloredOptions[@]}" >&2

        ## Prompt the user for input
        flushInput
        read -r -p "$message" userInput 
 
        ## Match that input to the corresponding element in the array
        if [[ $userInput =~ ^[0-9]+$ ]]; then
            opt=${options[$userInput]}   
        else 
            continue
        fi
        case $opt in
            "${MANUAL_MENU_OPTIONS[0]}")
                # menuUserVariables
                menuUserVariables
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[1]}")
                # Step 1.1: Enable APIs option
                enableApis
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[2]}")
                # Step 1.2: Create an organization
                createOrganization
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[3]}")
                # Step 1.3: Create an env
                createEnv
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[4]}")
                 # Step 1.3: Create an env group 
                createEnvGroup
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[5]}")
                 # Step 2.1: Create cluster 
                createClusterStep
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[6]}")
                 # Step 2.2: Download Apigee Helm Charts 
                downloadHelmCharts
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[7]}")
                 # Step 2.3: Create the Apigee Namespace 
                createNamespace
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[8]}")
                 # Step 2.4: Create Service Accounts 
                createServiceAccount
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[9]}")
                 # Step 2.5: Create TLS certs
                createTLSCerts
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[10]}")
                # Step 2.6: Create the Overrides
                version=$(handleVersions -r "${AVAILABLE_VERSIONS[@]}" \
                -v "${CHART_VERSION}" \
                -s "${OVERRIDES_YAML_NON_PROD_TEMPLATE_VERSIONS[@]}" 2> /dev/null)
                createOverrides --filename "${APIGEE_HELM_CHARTS_ABSOLUTE}/${OVERRIDES_FILE_NAME}" \
                --template "${!version}" \
                --pattern '\$[A-Z_]*'
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[11]}")
                 # Step 2.7: Enable Synchronizer access
                enableSynchronizer
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[12]}")
                # Step 2.8: install cert manager 
                installCertManager
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[13]}")
                # 2.9: Install Apigee Hybrid CRDs
                installCRDs
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[14]}")
                # 2.10: Check cluster readiness
                checkClusterReadiness
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[15]}")
                # 2.11: Install Apigee hybrid Using Helm
                installApigeeHybridHelm
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[16]}")
                # 2.12: [WIP](Optional) Configure Workload Identity
                configureWIF
                continue
                ;;
            "${MANUAL_MENU_OPTIONS[17]}")
                # 3.1: Expose Apigee ingress gateway
                exposeApigeeIngressGateway
                continue
                ;;
            "Quit")
                break
                ;;
            *) 
                echoWarning "[${FUNCNAME[*]}] Invalid option. Try typing a number again."
                ;;
        esac
        clear
    done
    return 0
}

automaticInstallater(){
    local version=
    FLAG_AUTOMATIC_INSTALLATION="true"
    local varsArray=
    local cacheKeys=($(readCache "keys_unsorted[]" "${CACHED_VALUES_FILE}"))

    varsArray=($(for el in "${cacheKeys[@]}"; do removeQuotes "$el"; done)) 

    echoDebug "[${FUNCNAME[*]}]varsArray==${varsArray[@]}"

    isKeyListFilledv2 "${varsArray[@]}" 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[isKeyListFilledv2]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    enableApis
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[enableApis]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    createOrganization
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createOrganization]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    createEnv
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createEnv]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    createEnvGroup
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createEnvGroup]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi
    if [[ "$NOMENU_OPTION" == 'all' ]]; then
        createClusterStep
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[createClusterStep]"
            FLAG_AUTOMATIC_INSTALLATION="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
            return 1
        fi
    fi

    downloadHelmCharts
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[downloadHelmCharts]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    createNamespace
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createNamespace]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    createServiceAccount
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createServiceAccount]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    createTLSCerts
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createTLSCerts]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    version=$(handleVersions -r "${AVAILABLE_VERSIONS[@]}" \
    -v "${CHART_VERSION}" \
    -s "${OVERRIDES_YAML_NON_PROD_TEMPLATE_VERSIONS[@]}")
    createOverrides --filename "${APIGEE_HELM_CHARTS_ABSOLUTE}/${OVERRIDES_FILE_NAME}" \
    --template "${!version}" \
    --pattern '\$[A-Z_]*'
    # createOverrides --filename "${APIGEE_HELM_CHARTS_ABSOLUTE}/${OVERRIDES_FILE_NAME}" \
    # --template "$OVERRIDES_NONPROD_YAML" \
    # --pattern '\$[A-Z_]*' \
    # --type "${PROD_TYPE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[createOverrides]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    enableSynchronizer
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[enableSynchronizer]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    installCertManager
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[installCertManager]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    installCRDs
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[installCRDs]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    if [[ "$(printf "%s\n%s" "${CHART_VERSION%.*}" "1.12" | sort -V | head -n1)" != "1.12" ]]; then
        checkClusterReadiness 
        if [[ "${PIPESTATUS[0]}" != "0" ]]; then
            logMessage -t 'err' "[checkClusterReadiness]"
            FLAG_AUTOMATIC_INSTALLATION="false"
            updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
            return 1
        fi
    else
        logMessage -t 'info' "Cluster Readiness Check was deprecated in v1.13."
    fi
    
    installApigeeHybridHelm
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[installApigeeHybridHelm]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    ## Add Flag to cache
    updateCacheWithCurrentEnvValues --cache-filename "$RUNTIME_FLAGS_FILE_ABSOLUTE" "FLAG_AUTOMATIC_INSTALLATION"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[updateCacheWithCurrentEnvValues]"
        FLAG_AUTOMATIC_INSTALLATION="false"
        updateCacheWithCurrentEnvValues --cache-filename "${RUNTIME_FLAGS_FILE_ABSOLUTE}" "FLAG_AUTOMATIC_INSTALLATION"
        return 1
    fi

    ## Check if the function was completed
    compareTwoStrings "$FLAG_AUTOMATIC_INSTALLATION" "true"
    return "$?" 
}


#################        WHIPTAIL MENUS        #################
wahm(){
    ## whiptail manual main menu
    local message="Choose an option:"
    local options=("${WHIPTAIL_AUTOMATIC_MENU_OPTIONS[@]}")
    local menuTitle="Apigee Hybrid Automatic Installation Menu"
    local userChoice=

    while true; do
        # userInput=
        ## add to env the current values for the flags
        declareCacheValues "$RUNTIME_FLAGS_FILE_ABSOLUTE"

        ## declare user variables
        declareCacheValues "$CACHED_VALUES_FILE_ABSOLUTE"

        ## flush the user input
        flushInput
        ## start menu
        userChoice=$(whiptailMenu --title "${menuTitle}" \
            --message "${message}" \
            --options "${options[@]}")
        [[ "$?" != '0' ]] && return 1
        case "$userChoice" in 
            "1")
                # menuUserVariables
                # menuUserVariables
                whiptailUserVars "Modify the following variables" "Select the variable to modify"
                continue
                ;;
            "2")
                automaticInstallater
                continue
                ;;
            *) 
                break
                ;;
        esac
        clear
    done

    return 0

}


automaticHybridMenu() {
   # The menu for automatic installation
    local message="Choose an option by typing a number: "
    local options=("${AUTOMATIC_MENU_OPTIONS[@]}" "Quit")
    local opt=
    local userInput=
    local coloredOptions=

    while true; do
        userInput=
        ## add to env the current values for the flags
        declareCacheValues "$RUNTIME_FLAGS_FILE_ABSOLUTE"

        ## declare user variables
        declareCacheValues "$CACHED_VALUES_FILE_ABSOLUTE"

        ## color the strings
        mapfile -t coloredOptions < <(colorArrayv2 "${MENU_OPTIONS_JSON}" ".[\"Automatic Menu Options\"][].name" ".[][]" ".name" ".flag")
        coloredOptions+=("Quit")
        
        ## Display the menu options
        displayMenuOptions "" "" "${coloredOptions[@]}"

        ## discard any previous bad input.

        ## Promt the user for input
        flushInput
        read -p "$message" userInput
        echoDebug "[${FUNCNAME[*]}] userInput==$userInput"
        ## Match that input to the corresponding element in the array
        if [[ $userInput =~ ^[0-9]+$ ]]; then
            opt=${options[$userInput]}   
        elif [[ -z "$userInput" ]]; then
            continue
        fi
        case $opt in
            "${AUTOMATIC_MENU_OPTIONS[0]}")
                # menuUserVariables
                menuUserVariables
                continue
                ;;
            "${AUTOMATIC_MENU_OPTIONS[1]}")
                automaticInstallater
                continue
                ;;
            "Quit")
                break
                ;;
            *) 
                echoWarning "[${FUNCNAME[*]}] Invalid option. Try typing a number again."
                ;;
        esac
        clear
    done
    return 0
}


##################       MENU FUNCTIONS       ##################
################################################################

################        HELPER FUNCTIONS        ################
AskValueVariable() {
    local inputVar=
    while [[ -z "$inputVar" ]]; do
        read -p "Current value of '${1}' is '${!1}'. Please insert the new value for '${1}': " inputVar
    done
    echo ${inputVar}
    return 0
}

BackToMenu() {
    # Routing user back to one of the menus
    # loading screen
    TransitionEffect 1

    if [ "$INSTALLATION_TYPE" = "AUTO" ]; then
        automaticHybridMenu
    elif  "$INSTALLATION_TYPE" = "MANUAL" ]; then
        manualHybridMenu
    fi
    return 0
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

initialization(){
    # Initial check of the files and values, when first booting up the program
    local checks=
    local fileNamesArray=("CACHED_VALUES_FILE" "RUNTIME_CACHE_FILE" "RUNTIME_FLAGS_FILE")
    local variablesNamesArray=("CACHE_VARIABLES_JSON" "RUNTIME_CACHE" "RUNTIME_FLAGS" )
    local fn=
    local vn=
    local i=
    # PRE-CHECKS
    ## check if the json values are correctly formatted for the json variables
    ## [WIP]
    
    ## initialize Variables
    ### Get the menu options for manual hybrid installation
    key='.["Manual Menu Options"][].name'
    mapfile -t MANUAL_MENU_OPTIONS < <(getJsonKeyValuev2 "$key" "$MENU_OPTIONS_JSON")

    ### get the menu flags 
    key='.["Manual Menu Options"][].flag'
    mapfile -t MANUAL_MENU_FLAGS < <(getJsonKeyValuev2 "$key" "$MENU_OPTIONS_JSON")

    ### automatic menu and flags
    key='.["Automatic Menu Options"][].flag'
    mapfile -t AUTOMATIC_MENU_FLAGS < <(getJsonKeyValuev2 "$key" "$MENU_OPTIONS_JSON")

    key='.["Automatic Menu Options"][].name'
    mapfile -t AUTOMATIC_MENU_OPTIONS < <(getJsonKeyValuev2 "$key" "$MENU_OPTIONS_JSON")
 
    ## all the flags
    key='.[][].flag'
    mapfile -t MENU_FLAGS < <(getJsonKeyValuev2 "$key" "$MENU_OPTIONS_JSON")
    
    ###  Generate the Runtime Flags json variable
    RUNTIME_FLAGS="{}"
    for each in "${MENU_FLAGS[@]}"; do
        echoDebug "[${FUNCNAME[*]}][${LINENO}] each==$each"
        RUNTIME_FLAGS=$( jq ". + { \"$each\": \"${!each}\"  }" <<<$RUNTIME_FLAGS)
    done
   
    
    ## Check if the env values are filled
    isKeyListFilled "${fileNamesArray[@]}" "${variablesNamesArray[@]}" "MANUAL_MENU_FLAGS" "MANUAL_MENU_OPTIONS" "AUTOMATIC_MENU_FLAGS" "AUTOMATIC_MENU_OPTIONS"
    checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME[*]}][isKeyListFilled][${LINENO}] VERY BAD!"
    if [[ "$?" != "0" ]]; then return 1; fi

    for ((i=0; i<${#variablesNamesArray[@]}; i++)); do
        echoDebug "[${FUNCNAME[*]}] for loop:
            fn=${fileNamesArray[$i]}
            vn=${variablesNamesArray[$i]}">&2
        fn=${fileNamesArray[$i]}
        vn=${variablesNamesArray[$i]}
        
        # Check if the exists
        checks=$(isFileEmpty "${!fileNamesArray[$i]}"; echo "$?") 
        checkAndDisplayMessage -mt "DEBUG" "$checks" "[${FUNCNAME[*]}][isFileEmpty][${LINENO}] File is not empty variable Name == $fn and it's value == ${!fn}"
        # if [[ "$?" != "0" ]]; then return 1; fi

        # createAndPopulateFile "${!fileNamesArray[$i]}" "${!variablesNamesArray[$i]}"
        createAndPopulateFile "${!fn}" "${!vn}"
        checkAndDisplayMessage -mt "DEBUG" $? "[${FUNCNAME[*]}][createAndPopulateFile][${LINENO}]"
        # if [[ "$?" != "0" ]]; then return 1; fi

        declareCacheValues "${!fn}"
        checkAndDisplayMessage $? "[ERROR][${FUNCNAME[*]}][declareCacheValues][${LINENO}]"
         if [[ "$?" != "0" ]]; then return 1; fi

    done
    ## create FLAGS arrays
    local temp=($(readCache "keys_unsorted[]" "${RUNTIME_FLAGS_FILE_ABSOLUTE}"))

    RUNTIME_FLAGS_ARRAY=($(for el in "${temp[@]}"; do removeQuotes "$el"; done)) 
    declare -g "RUNTIME_FLAGS_ARRAY"="${RUNTIME_FLAGS_ARRAY[@]}"

    ## initialize the version list:
    key='.[].[].version'
    mapfile -t AVAILABLE_VERSIONS < <(getJsonKeyValuev2 "$key" "$AVAILABLE_VERSIONS_JSON")
    [[ "$?" != 0 ]] &&  logMessage -t 'e' "maping AVAILABLE_VERSIONS=='${AVAILABLE_VERSIONS[@]}' failed." && return 1

    key='.[].[].overridesTemplateNonProd'
    mapfile -t OVERRIDES_YAML_NON_PROD_TEMPLATE_VERSIONS < <(getJsonKeyValuev2 "$key" "$AVAILABLE_VERSIONS_JSON")
    [[ "$?" != 0 ]] &&  logMessage -t 'e' "maping OVERRIDES_YAML_NON_PROD_TEMPLATE_VERSIONS=='${OVERRIDES_YAML_NON_PROD_TEMPLATE_VERSIONS[@]}' failed." && return 1
    ### NEEDS REWORK WITH KEY PAIRS IN BASH   

    ## whiptail menu
    WHIPTAIL_MANUAL_MENU_OPTIONS=()
    WHIPTAIL_AUTOMATIC_MENU_OPTIONS=()
    i=
    # read -r -a WHIPTAIL_MANUAL_MENU_OPTIONS < <(numberArrayElements "${MANUAL_MENU_OPTIONS[@]}")
    # WHIPTAIL_MANUAL_MENU_OPTIONS=("$(numberArrayElements "${MANUAL_MENU_OPTIONS[@]}")")
    while IFS= read -r -d '' i; do
        WHIPTAIL_MANUAL_MENU_OPTIONS+=("$i")
    done < <(numberArrayElements "${MANUAL_MENU_OPTIONS[@]}")
    WHIPTAIL_MANUAL_MENU_OPTIONS=("${WHIPTAIL_MANUAL_MENU_OPTIONS[@]:1}")
    
    while IFS= read -r -d '' i; do
        WHIPTAIL_AUTOMATIC_MENU_OPTIONS+=("$i")
    done < <(numberArrayElements "${AUTOMATIC_MENU_OPTIONS[@]}")
    WHIPTAIL_AUTOMATIC_MENU_OPTIONS=("${WHIPTAIL_AUTOMATIC_MENU_OPTIONS[@]:1}")
    
    return 0


}


# goToNextStep() {
#     # Sends the user to the next step of the installation process
#     # $1 = The function name for the next installation function
#     # $2 = The function name in case the the user chooses to go back to the previous menu or step
#     # $3 = Message prompt
#     if declare -f "$1" > /dev/null && $(confirmYes "$3") ; then
#         # echo "----yes" 
#         "$@"
#     else
#         if declare -f "$2" > /dev/null; then
#             # echo "---no"
#             shift
#             "$@"
#         else
#             # [ERROR]
#             echoError "[${FUNCNAME[*]}] Functions '$1' and '$2' not found!" >&2
#             return 1
#         fi
#     fi

# }

connectToCluster(){
    local clusterRegion=
    local projectID=
    local clusterName=
    while :; do
       case $1 in
            -h|-\?|--help)
                echo " #[HELP OPTIONS]
                "
                exit
                ;;
            --region)       
                # ensure that it is specified
                if [ "${2}" ]; then
                    clusterRegion=$2
                    shift
                else
                    checkAndDisplayMessage -mt "ERROR" "1" "[${FUNCNAME[*]}] '--region' flag is not specified!"
                    return 1
                fi
                ;;
            --project)               
                if [ "${2}" ]; then
                    projectID=$2
                    shift
                else
                    checkAndDisplayMessage -mt "ERROR" "1" "[${FUNCNAME[*]}] '--project' flag is not specified!"
                    return 1
                fi
                ;;
            *)              # Default case: no more options, therefore break.
                break
        esac
        shift
    done
    clusterName=$1
    gcloud container clusters get-credentials $clusterName \
        --region $clusterRegion \
        --project $projectID \
        --format="json" \
        --quiet
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'error' "[gcloud container clusters get-credentials $clusterName]
        --region $clusterRegion \
        --project $projectID \
        --format="json" \
        --quiet"
        return 1
    fi
    return 0
}


deleteSAKeys() {
    # Deletes an array of service account keys
    # $1 = SA name
    # $2 = project ID 
    # $@ = key IDs array
    local key=
    local checks=0
    local saName=$1
    local projectID=$2
    shift 2
    local keyArray=("$@")
    for key in "${keyArray[@]}"; do
        # echo "key = $key" 
        deleteSAKey $saName $projectID $key
        if [[ $? == 1 ]]; then
            logMessage -t 'error' "[deleteSAKey] The deletion of key=$key for SA $saName@$projectID.iam.gserviceaccount.com was unsuccessful." >&2
            checks=1
        fi
    done
    return "$checks"
}

deleteSAKey() {
    # Delete a single service account key
    # $1 = SA name
    # $2 = project ID 
    # $3 = key ID
    gcloud iam service-accounts keys delete $3 \
        --iam-account="$1@$2.iam.gserviceaccount.com" \
        --quiet \
        --format=json
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'error' "[gcloud iam service-accounts keys delete $3 \
        --iam-account=$1@$2.iam.gserviceaccount.com \
        --quiet \
        --format=json]"
        return 1
    fi
    return 0
}


setGoogleProject(){
    # sets the google project in browser
    # $1 = name of the google project
    gcloud config set project "$1"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'error' "[gcloud config set project $1]"
        return 1
    fi
    return 0
}

getApigeeIngressGatewayIP() {
    local output=
    local ingressName="$1"
    output=$(kubectl get svc -n apigee -l app=apigee-ingressgateway -l ingress_name=${ingressName} -o json | jq -r ".items[].status.loadBalancer.ingress[].ip")    
    logMessage -t 'debug' "IP==$output">&2
    # verify 
    verifyIPv4 "$output"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'warn' "missing variables ${output[*]}"
        return 1
    fi
    
    # output
    echo "${output}"
    return 0
}

checkApigeeIngressHealth(){
    local output
    local domain="$1"
    local lbIP="$2"

    curlOutput=$(curl -H 'User-Agent: GoogleHC' https://${domain}/healthz/ingress -k \
        --resolve "${domain}:443:${lbIP}" \
        -s -o "/dev/null" -w "%{http_code}")

    echoInfo "[${FUNCNAME[*]}] Apigee Ingress status $curlOutput" >&2

    [[ "$curlOutput" != "200" ]]  && return 1

    return 0
}


################        HELPER FUNCTIONS        ################
################################################################

####################     MAIN FUNCTIONS     ####################
mainFlagsHandling() {
    # $@ array of inputs for main.sh
    local mainFlagsArray=("$@")
    while :; do
        ## Check for empty string
        [ -z "$1" ] && return 0
        case ${1,,} in 
            --debug|-v)       
                declare -g "DEBUG_MODE"="true"
                ;;
            -auto | --auto |--install=auto)
                [[ -n "$INSTALLATION_TYPE" ]] && exit 1          
                declare -g "INSTALLATION_TYPE"="AUTO"
                ;;
            -manual| --manual |--install=manual)
                [[ -n "$INSTALLATION_TYPE" ]] && exit 1       
                declare -g "INSTALLATION_TYPE"="MANUAL"
                ;;
            -nm| --no-menu |--install=no-menu)
                [[ -n "$INSTALLATION_TYPE" ]] && exit 1       
                declare -g "INSTALLATION_TYPE"="NOMENU"
                NOMENU_OPTION='all'
                if [[ "${2,,}" == 'no-cluster' ]]; then 
                    NOMENU_OPTION='no-cluster'
                fi
                declare -g "NOMENU_OPTION"="${NOMENU_OPTION}"
                ;;
            --reset-flags)       
                updateCachewithEmptyValues "$RUNTIME_FLAGS_FILE_ABSOLUTE" "${RUNTIME_FLAGS_ARRAY[@]}" 
                ;;
            --erase|-e)
                [[ -n "$INSTALLATION_TYPE" && "$INSTALLATION_TYPE" != 'ERASE'  ]] && exit 1
                INSTALLATION_TYPE='ERASE'
                if [ "${2}" ] && [[ " ${ERASE_OPTIONS[@]} " =~ " ${2^^} " ]] && [[ "${ERASE_LIST^^}" != "${ERASE_OPTIONS^^}" ]]; then
                    ## add element
                    ERASE_LIST+=("${2^^}")
                    declare -g ERASE_LIST
                    shift
                elif [[ "${2^^}" == "ALL" ]]; then 
                    ERASE_LIST=("${ERASE_OPTIONS[@]}")
                    declare -g ERASE_LIST
                    shift
                else
                    local messageErase=$(for each in ${ERASE_OPTIONS[@]}; do echo -e " --erase ${each}"; done)
                    echo "[${FUNCNAME[*]}] '--erase' requires a non-empty option argument, part of the permitted list of arguments:\n${messageErase,,}" >&2
                    return 1
                fi
                ;;
            -h|-\?|--help)
                INSTALLATION_TYPE='HELP'
                break
                ;;
            *)              # Default case: no more options, therefore break.
                exit 1
                ;;
        esac
        shift
    done
    return 0
}


