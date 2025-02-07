#!/bin/bash


createStorageClass() {
    local sclyVar=
    local sclyPath=
    local runtimeCacheFile=
    local projectID=
    local clusterName=
    local clusterLocation=
    local kubectlOutput=
    local curlOutput=
    #
    local keyArray=("projectID" "runtimeCacheFile" "sclyVar" "sclyPath" "clusterName" "clusterLocation" "runtimeFlagsFileAbsolute")
    FLAG_CREATE_STORAGE_CLASS="true"

   ### FLAG HANDLING ###
    while :; do
        case $1 in
            --project) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    projectID=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--project' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --cluster) 
                # ensure that value is specified
                if [ "${2}" ]; then
                    clusterName=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--cluster' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --region) 
                # ensure that value is specified
                if [ "${2}" ]; then
                    clusterLocation=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--region' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --storageclass-template) 
                # ensure that value is specified
                if [ "${2}" ]; then
                    sclyVar=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--storageclass-template' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --storageclass-file) 
                # ensure that value is specified
                if [ "${2}" ]; then
                    sclyPath=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--storageclass-file' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --runtime-cachefile) 
                # ensure that value is specified
                if [ "${2}" ]; then
                    runtimeCacheFile=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--runtime-cachefile' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            *)
                break
        esac
        shift
    done

    local runtimeFlagsFileAbsolute="${MAIN_SCRIPT_LOCATION}/${runtimeCacheFile}"

    echoDebug "[${FUNCNAME}] Input values:
    projectID=$projectID
    runtimeCacheFile=$runtimeCacheFile
    clusterName=$clusterName
    clusterLocation=$clusterLocation
    storageclasstemplate=$sclyVar
    storageclassFile=$sclyPath">&2

    # Set project
    setGoogleProject $projectID
    # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][setGoogleProject $projectID] Could not set project $projectID!"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][setGoogleProject $projectID] Could not set project $projectID!"    
    if [[ "$?" != "0" ]]; then return 1; fi

    # Print token
    export TOKEN=$(gcloud auth print-access-token)

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"

    isKeyListFilledv2 "TOKEN" "MAIN_SCRIPT_LOCATION" "${keyArray[@]}"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][isKeyFilled]"    
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Connect to cluster
    connectToCluster --region $clusterLocation --project $projectID $clusterName
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][connectToCluster] Connecting to $clusterName cluster failed."
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Configure persistent solid state disk storage for Cassandra.
    ## Create the storageclass.yaml file
    createAndPopulateFile "${sclyPath}" "${sclyVar}"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][createAndPopulateFile]STORAGE_CLASS_YAML_FILE==$sclyPath"
    if [[ "$?" != "0" ]]; then return 1; fi

    echoDebug "[${FUNCNAME}]cat the storagee file ${sclyPath}: $(cat ${sclyPath})">&2
    ## Apply the storageclasss to cluster
    kubectl apply -f "${sclyPath}"  | tee -a "${ABS_LOGS_FILE}"
    ### check if command was successful
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][kubectl apply -f ${sclyPath}] Applying the storageclass.yaml in $clusterName cluster failed."
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Change the default storage
    kubectl patch storageclass standard-rwo \
        -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' \
        | tee -a "${ABS_LOGS_FILE}"
    ### check if command was successful
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][kubectl patch storageclass standard-rwo] Changing the default storage-false in $clusterName cluster failed."
    if [[ "$?" != "0" ]]; then return 1; fi

    kubectl patch storageclass apigee-sc \
        -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' \
        | tee -a "${ABS_LOGS_FILE}"
    ### check if command was successful
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][ kubectl patch storageclass apigee-sc] Changing the default storage to apigee-sc in $clusterName cluster failed."
    if [[ "$?" != "0" ]]; then return 1; fi

    ## visual confirmation
    kubectlOutput=$(kubectl get sc -o=json)
    curlOutput=$(jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | .metadata.name' <<< "$kubectlOutput")
    compareTwoStrings "apigee-sc" "$curlOutput"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_STORAGE_CLASS" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}]current default storage is $curlOutput"
    if [[ "$?" == "0" ]]; then echoInfo "[${FUNCNAME}] apigee-sc is the default storage" >&2; fi

    ## Check if the function was completed
    echoDebug "[${FUNCNAME}] FLAG_CREATE_STORAGE_CLASS==$$FLAG_CREATE_STORAGE_CLASS"
    compareTwoStrings "$FLAG_CREATE_STORAGE_CLASS" "true"
    return "$?" 
}

createClusterNodePool() {
    #
    local projectID=
    local runtimeCacheFile=
    local nodePoolName=
    local clusterName=
    local clusterLocation=
    local clusterMachineType=
    local clusterImageType=
    local clusterDiskType=
    local clusterDiskSize=
    local clusterNumNodes=
    #
    local curlOutput=
    local gcloudOutput=
    local keyLoop=
    local runtimeFlagsFileAbsolute=
    local keyArray=("projectID" "runtimeCacheFile" "nodePoolName" "clusterName" "clusterLocation" "clusterMachineType" "clusterImageType" "clusterDiskType" "clusterDiskSize" "clusterNumNodes" "runtimeFlagsFileAbsolute")
    FLAG_CREATE_CLUSTER_NODE_POOL=true

   ### FLAG HANDLING ###
    while :; do
        case $1 in
            --nodepool) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    nodePoolName=$2
                    shift
                else
                    echoError "[createOverrides] '--nodepool' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --project) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    projectID=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--project' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --cluster) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterName=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--cluster' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --region) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterLocation=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--region' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --machine-type) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterMachineType=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--machine-type' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --image-type) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterImageType=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--image-type' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --disk-type) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterDiskType=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--disk-type' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --disk-size) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterDiskSize=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--disk-size' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --num-nodes) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterNumNodes=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--num-nodes' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --runtime-cachefile) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    runtimeCacheFile=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--runtime-cachefile' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            *)
                break
        esac
        shift
    done

    local runtimeFlagsFileAbsolute="${MAIN_SCRIPT_LOCATION}/${runtimeCacheFile}"

    echoDebug "[${FUNCNAME}] Input values:
    nodePoolName=$nodePoolName
    projectID=$projectID
    runtimeCacheFile=$runtimeCacheFile
    clusterName=$clusterName
    clusterLocation=$clusterLocation
    clusterMachineType=$clusterMachineType
    clusterImageType=$clusterImageType
    clusterDiskType=$clusterDiskType
    clusterDiskSize=$clusterDiskSize
    clusterNumNodes=$clusterNumNodes">&2

    # Set project
    setGoogleProject $projectID
    # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][setGoogleProject $projectID] Could not set project $projectID!"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_CLUSTER_NODE_POOL" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][setGoogleProject $projectID] Could not set project $projectID!"    
    if [[ "$?" != "0" ]]; then return 1; fi

    # Print token
    export TOKEN=$(gcloud auth print-access-token)

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"

    isKeyListFilledv2 "TOKEN" "MAIN_SCRIPT_LOCATION" "${keyArray[@]}"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_CLUSTER_NODE_POOL" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][isKeyFilled]"    
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Connect to cluster
    connectToCluster --region $clusterLocation --project $projectID $clusterName
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_CLUSTER_NODE_POOL" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][connectToCluster] Connecting to $clusterName cluster failed."
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Create the apigee-datastore node-pool
    gcloudOutput=$(gcloud container node-pools create "$nodePoolName" \
        --project "$projectID" \
        --cluster "$clusterName" \
        --region "$clusterLocation" \
        --machine-type "$clusterMachineType" \
        --image-type "$clusterImageType" \
        --disk-type "$clusterDiskType" \
        --disk-size "$clusterDiskSize" \
        --metadata disable-legacy-endpoints=true \
        --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
        --num-nodes "$clusterNumNodes" \
        --enable-autoupgrade \
        --enable-autorepair \
        --max-surge-upgrade 0 \
        --max-unavailable-upgrade 0 \
        --format="json" \
        --quiet)
    echoDebug "[${FUNCNAME}][gcloud container node-pools create "$nodePoolName"]
        --project "$projectID" 
        --cluster "$clusterName" 
        --region "$clusterLocation" 
        --machine-type "$clusterMachineType" 
        --image-type "$clusterImageType" 
        --disk-type "$clusterDiskType" 
        --disk-size "$clusterDiskSize" 
        --metadata disable-legacy-endpoints=true 
        --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" 
        --num-nodes "$clusterNumNodes" 
        --enable-autoupgrade 
        --enable-autorepair 
        --max-surge-upgrade 0 
        --max-unavailable-upgrade 0
    Output:
    $gcloudOutput" >&2
    
    keyLoop=".status"
    ## Poll for state of the cluster
    loopCurlv2 -H "Authorization: Bearer $TOKEN" \
        --key "$keyLoop" --expected-value "RUNNING" \
        --total-wait-time "1200" --polling-interval "60" -m "Waiting cluster to be reconciled." \
        "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName/nodePools/$nodePoolName"
    
    checkAndDisplayMessage -mt "WARNING" "$?" "[${FUNCNAME}][loopCurlv2]$nodePoolName"

    ### check if command was successful first with curl and then with checks
    curlStatus=$(getCurlStatus "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName/nodePools/$nodePoolName")
      
    if [[ "$curlStatus" =~ ^[2][0-9][0-9]$ ]]; then 
        echoInfo "[${FUNCNAME}] nodepool $nodePoolName is present in the cluster."
    elif [[ "$curlStatus" == "409" ]]  || [[ "$(jq -r '.error.status' <<< $curlStatus)" == "409" ]]; then
        echoWarning "[${FUNCNAME}] nodepool $nodePoolName already exists."
    else
        echoWarning "[${FUNCNAME}] Something went wrong with creating nodepool $nodePoolName inside cluster $clusterName in project $projectID. Status was $curlStatus "
        FLAG_CREATE_CLUSTER_NODE_POOL="failed"
        return 1
    fi
 
    ## Check if the function was completed
    echoDebug "[${FUNCNAME}] FLAG_CREATE_CLUSTER_NODE_POOL==$$FLAG_CREATE_CLUSTER_NODE_POOL"
    compareTwoStrings "$FLAG_CREATE_CLUSTER_NODE_POOL" "true"
    return "$?" 
}

deleteNodePool() {
    #
    local projectID=
    local runtimeCacheFile=
    local nodePoolName=
    local clusterName=
    local clusterLocation=
    #
    local curlOutput=
    local curlStatus=
    local gcloudOutput=
    local keyLoop=
    local runtimeFlagsFileAbsolute=
    local keyArray=("projectID" "runtimeCacheFile" "nodePoolName" "clusterName" "clusterLocation" "runtimeFlagsFileAbsolute")
    FLAG_DELETE_CLUSTER_NODE_POOL=true

   ### FLAG HANDLING ###
    while :; do
        case $1 in
            --nodepool) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    nodePoolName=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--nodepool' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --project) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    projectID=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--project' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --cluster) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterName=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--cluster' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --region) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterLocation=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--region' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --runtime-cachefile) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    runtimeCacheFile=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--runtime-cachefile' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            *)
                break
        esac
        shift
    done

    local runtimeFlagsFileAbsolute="${MAIN_SCRIPT_LOCATION}/${runtimeCacheFile}"

    echoDebug "[] Input values:
    nodePoolName=$nodePoolName
    projectID=$projectID
    runtimeCacheFile=$runtimeCacheFile
    clusterName=$clusterName
    clusterLocation=$clusterLocation">&2

    # Set project
    setGoogleProject $projectID
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_DELETE_CLUSTER_NODE_POOL" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][setGoogleProject $projectID]"    
    if [[ "$?" != "0" ]]; then return 1; fi


    # Print token
    export TOKEN=$(gcloud auth print-access-token)

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"

    isKeyListFilledv2 "TOKEN" "MAIN_SCRIPT_LOCATION" "${keyArray[@]}"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_DELETE_CLUSTER_NODE_POOL" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][isKeyFilled]"    
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Connect to cluster
    connectToCluster --region $clusterLocation --project $projectID $clusterName
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_DELETE_CLUSTER_NODE_POOL" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][connectToCluster] Connecting to $clusterName cluster failed."
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Delete the nodepool
    gcloudOutput=$(gcloud container node-pools delete $nodePoolName \
        --project "$projectID" \
        --cluster "$clusterName" \
        --region "$clusterLocation" \
        --format="json" \
        --quiet)

    echoDebug "[${FUNCNAME}][gcloud container node-pools delete $nodePoolName]
        --project "$projectID" 
        --cluster "$clusterName" 
        --region "$clusterLocation" 
        --format="json" 
        --quiet
    Output:
    $gcloudOutput" >&2
    
    keyLoop=".error.status"
    # Poll for state of the nodepool
    loopCurlv2 -H "Authorization: Bearer $TOKEN" \
        --key "$keyLoop" --expected-value "NOT_FOUND" \
        --total-wait-time "1200" --polling-interval "60" -m "Deleting cluster nodepool ${nodePoolName}" \
        "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName/nodePools/$nodePoolName"
    
    checkAndDisplayMessage -mt "WARNING" "$?" "[${FUNCNAME}][loopCurlv2]$nodePoolName"

    ### check if command was successful first with curl and then with checks
    curlStatus=$(getCurlStatus "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName/nodePools/$nodePoolName")
    if [[ "$curlStatus" == "404" ]]; then 
            echoInfo "[${FUNCNAME}] nodepool $nodePoolName is deleted!"
    else
        echoError "[${FUNCNAME}] Something went wrong with deleting nodepool $nodePoolName inside cluster $clusterName in project $projectID. Status was $curlStatus "
        FLAG_DELETE_CLUSTER_NODE_POOL="failed"
        return 1
    fi

    ## Check if the function was completed
    echoDebug "[${FUNCNAME}] FLAG_DELETE_CLUSTER_NODE_POOL==$$FLAG_DELETE_CLUSTER_NODE_POOL"
    compareTwoStrings "$FLAG_DELETE_CLUSTER_NODE_POOL" "true"
    return "$?" 
}

createCluster() {
    #
    local projectID=
    local runtimeCacheFile=
    local clusterName=
    local clusterLocation=
    local vpcNetwork=
    local clusterChannel=
    local clusterMachineType=
    local clusterImageType=
    local clusterDiskType=
    local clusterDiskSize=
    local clusterNumNodes=
    #
    local curlOutput=
    local gcloudOutput=
    local keyLoop=
    local runtimeFlagsFileAbsolute=

    local keyArray=("projectID" "runtimeCacheFile" "vpcNetwork" "clusterChannel" "clusterName" "clusterLocation" "clusterMachineType" "clusterImageType" "clusterDiskType" "clusterDiskSize" "clusterNumNodes" "runtimeFlagsFileAbsolute")
    FLAG_CREATE_CLUSTER=true

   ### FLAG HANDLING ###
    while :; do
        case $1 in
            --project) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    projectID=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--project' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --cluster) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterName=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--cluster' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --region) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterLocation=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--region' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --release-channel) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterChannel=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--release-channel' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --network) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    vpcNetwork=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--network' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --machine-type) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterMachineType=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--machine-type' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --image-type) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterImageType=$2
                    shift
                else
                    echoError "[createOverrides] '--image-type' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --disk-type) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterDiskType=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--disk-type' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --disk-size) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterDiskSize=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--disk-size' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --num-nodes) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterNumNodes=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--num-nodes' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --runtime-cachefile) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    runtimeCacheFile=$2
                    shift
                else
                    echoError "[${FUNCNAME}] '--runtime-cachefile' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            *)
                break
        esac
        shift
    done

    local runtimeFlagsFileAbsolute="${MAIN_SCRIPT_LOCATION}/${runtimeCacheFile}"

    echoDebug "[${FUNCNAME}] Input values:
    projectID=$projectID
    runtimeCacheFile=$runtimeCacheFile
    clusterName=$clusterName
    clusterLocation=$clusterLocation
    vpcNetwork=$vpcNetwork
    clusterChannel=$clusterChannel
    clusterMachineType=$clusterMachineType
    clusterImageType=$clusterImageType
    clusterDiskType=$clusterDiskType
    clusterDiskSize=$clusterDiskSize
    clusterNumNodes=$clusterNumNodes">&2

    # Set project
    setGoogleProject $projectID
    # checkAndDisplayMessage -mt "ERROR" "$?" "[${FUNCNAME}][setGoogleProject $projectID] Could not set project $projectID!"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_CLUSTER" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][setGoogleProject $projectID] Could not set project $projectID!"    
    if [[ "$?" != "0" ]]; then return 1; fi

    # Print token
    export TOKEN=$(gcloud auth print-access-token)

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"

    isKeyListFilledv2 "TOKEN" "MAIN_SCRIPT_LOCATION" "${keyArray[@]}"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_CLUSTER" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}][isKeyFilled]"    
    if [[ "$?" != "0" ]]; then return 1; fi

    ## Create the regional cluster

    gcloudOutput=$(gcloud container clusters create $clusterName \
        --project "$projectID" \
        --region $clusterLocation \
        --release-channel $clusterChannel \
        --num-nodes $clusterNumNodes \
        --machine-type "$clusterMachineType" \
        --image-type "$clusterImageType" \
        --disk-type "$clusterDiskType" \
        --disk-size "$clusterDiskSize" \
        --default-max-pods-per-node "110" \
        --no-enable-intra-node-visibility \
        --enable-ip-alias \
        --network "projects/${projectID}/global/networks/${vpcNetwork}" \
        --subnetwork "projects/${projectID}/regions/${clusterLocation}/subnetworks/${vpcNetwork}" \
        --security-posture=standard \
        --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver \
        --enable-shielded-nodes \
        --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,CADVISOR,KUBELET \
        --logging=SYSTEM,WORKLOAD \
        --workload-vulnerability-scanning=disabled \
        --no-enable-master-authorized-networks \
        --enable-autoupgrade \
        --enable-autorepair \
        --max-surge-upgrade 0 \
        --max-unavailable-upgrade 0 \
        --binauthz-evaluation-mode=DISABLED \
        --enable-managed-prometheus \
        --metadata disable-legacy-endpoints=true \
        --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" \
        --enable-shielded-nodes \
        --format="json" \
        --quiet)

    echoDebug "[${FUNCNAME}][gcloud container clusters create $clusterName]
        --project "$projectID" 
        --region $clusterLocation 
        --release-channel $clusterChannel 
        --num-nodes $clusterNumNodes 
        --machine-type "$clusterMachineType" 
        --image-type "$clusterImageType" 
        --disk-type "$clusterDiskType" 
        --disk-size "$clusterDiskSize" 
        --default-max-pods-per-node "110"
        --no-enable-intra-node-visibility 
        --enable-ip-alias 
        --network "projects/$projectID/global/networks/$vpcNetwork" 
        --subnetwork "projects/$projectID/regions/$clusterLocation/subnetworks/$vpcNetwork" 
        --security-posture=standard 
        --addons HorizontalPodAutoscaling,HttpLoadBalancing,GcePersistentDiskCsiDriver 
        --enable-shielded-nodes 
        --monitoring=SYSTEM,STORAGE,POD,DEPLOYMENT,STATEFULSET,DAEMONSET,HPA,CADVISOR,KUBELET 
        --logging=SYSTEM,WORKLOAD 
        --workload-vulnerability-scanning=disabled 
        --no-enable-master-authorized-networks 
        --enable-autoupgrade 
        --enable-autorepair 
        --max-surge-upgrade 0 
        --max-unavailable-upgrade 0 
        --binauthz-evaluation-mode=DISABLED 
        --enable-managed-prometheus 
        --metadata disable-legacy-endpoints=true 
        --scopes "https://www.googleapis.com/auth/devstorage.read_only","https://www.googleapis.com/auth/logging.write","https://www.googleapis.com/auth/monitoring","https://www.googleapis.com/auth/servicecontrol","https://www.googleapis.com/auth/service.management.readonly","https://www.googleapis.com/auth/trace.append" 
        --enable-shielded-nodes 
        --format="json" 
        --quiet
    Output:
    $gcloudOutput" >&2

    keyLoop=".status"

    ## Poll for state of the envgroup
    loopCurlv2 -H "Authorization: Bearer $TOKEN" \
        --key "$keyLoop" --expected-value "RUNNING" \
        --total-wait-time "1200" --polling-interval "60" -m "Creating & reconciling cluster ${clusterName}" \
        "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName"
    
    checkAndDisplayMessage -mt "WARNING" "$?" "[${FUNCNAME}][loopCurlv2]cluster $clusterName"

    ### check if command was successful first with curl and then with checks
    curlOutput=$(getCurlStatus "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName")
    compareTwoStrings "200" "${curlOutput}"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_CLUSTER" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME}]The cluster API endpoint is not reporting status 200, but status ${curlOutput}"

    ## pol for the nodes status
    kubectl get nodes -o wide 2>&1
    
    ## Check if the function was completed
    echoDebug "[${FUNCNAME}] FLAG_CREATE_CLUSTER==${FLAG_CREATE_CLUSTER}"
    compareTwoStrings "$FLAG_CREATE_CLUSTER" "true"
    return "$?" 
}



deleteCluster() {
    #
    local projectID=
    local runtimeCacheFile=
    local clusterName=
    local clusterLocation=
    #
    local curlOutput=
    local gcloudOutput=
    local keyLoop=
    local runtimeFlagsFileAbsolute=

    local keyArray=("projectID" "runtimeCacheFile" "clusterName" "clusterLocation")
    FLAG_DELETE_CLUSTER=true

   ### FLAG HANDLING ###
    while :; do
        case $1 in
            --project) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    projectID=$2
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '--project' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --cluster) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterName=$2
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '--cluster' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --region) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    clusterLocation=$2
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '--region' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            --runtime-cachefile) 
                # ensure that value is specified
                
                if [ "${2}" ]; then
                    runtimeCacheFile=$2
                    shift
                else
                    echoError "[${FUNCNAME[*]}] '--runtime-cachefile' requires a non-empty option argument" >&2
                    return 1
                fi
                ;;
            *)
                break
        esac
        shift
    done

    local runtimeFlagsFileAbsolute="${MAIN_SCRIPT_LOCATION}/${runtimeCacheFile}"

    echoDebug "[${FUNCNAME[*]}] Input values:
    projectID=$projectID
    runtimeCacheFile=$runtimeCacheFile
    clusterName=$clusterName
    clusterLocation=$clusterLocation">&2



    # Set project
    setGoogleProject $projectID
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_DELETE_CLUSTER" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME[*]}][setGoogleProject $projectID] Could not set project $projectID!"    
    [[ "$?" != "0" ]] && return 1

    # Print token
    export TOKEN=$(gcloud auth print-access-token)

    # Set location
    cd "$MAIN_SCRIPT_LOCATION"

    isKeyListFilledv2 "TOKEN" "MAIN_SCRIPT_LOCATION" "${keyArray[@]}"
    checkChecksAndFlag -mt "ERROR" -ff "$runtimeFlagsFileAbsolute" \
        -f "FLAG_CREATE_CLUSTER" -fv "failed" -fc "1" "$?" \
        "[${FUNCNAME[*]}][isKeyFilled] Some of the values are not properly filled!"    
    [[ "$?" != "0" ]] && return 1

    ## Create the regional cluster

    gcloudOutput=$(gcloud container clusters delete $clusterName \
        --project "$projectID" \
        --region $clusterLocation \
        --format="json" \
        --quiet)

    echoDebug "[${FUNCNAME[*]}][gcloud container clusters delete $clusterName]
       gcloud container clusters delete $clusterName \
        --project "$projectID" \
        --region $clusterLocation \
        --format="json" \
        --quiet
    Output:
    $gcloudOutput" >&2

    keyLoop=".error.status"

    ## Poll for state of the 
    loopCurlv2 -H "Authorization: Bearer $TOKEN" \
        --key "$keyLoop" --expected-value "NOT_FOUND" \
        --total-wait-time "1200" --polling-interval "60" -m "Deleting cluster ${clusterName}" \
        "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName"
    
    checkAndDisplayMessage -mt "WARNING" "$?" "[${FUNCNAME}][loopCurlv2] Deleting cluster $clusterName may not have succeeded."


    ### check if command was successful first with curl and then with checks
    curlStatus=$(getCurlStatus "https://container.googleapis.com/v1beta1/projects/$projectID/locations/$clusterLocation/clusters/$clusterName")
    if [[ "$curlStatus" == "404" ]]; then 
            echoInfo "[${FUNCNAME[*]}] cluster $clusterName not found."
    else
        echoError "[${FUNCNAME[*]}] Something went wrong with deleting cluster $clusterName in project $projectID. Status was $curlStatus "
        FLAG_DELETE_CLUSTER="failed"
        return 1
    fi

    ## Check if the function was completed
    echoDebug "[${FUNCNAME[*]}] FLAG_DELETE_CLUSTER==${FLAG_DELETE_CLUSTER}"
    compareTwoStrings "$FLAG_DELETE_CLUSTER" "true"
    return "$?" 
}
