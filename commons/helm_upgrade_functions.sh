#!/bin/bash

####################     HELM FUNCTIONS     ####################
################################################################
# GLOBAL INPUT VARS
# ABS_LOGS_FILE = absolute path to the logs file
# message_functions.sh library with logMessage() function for logging, TransitionEffect for waiting.

[[ -z "${ABS_LOGS_FILE}" ]] && ABS_LOGS_FILE='/dev/null'

# LOCAL INPUT
## overridesFileName
## runtimeFlagsFilepath
## namespace


helmUpgradeOperator(){
    # Subfunction to install apigee-operator
    # $1 = OVERRIDES_FILE_NAME.
    local overridesFileName="$1"
    local helmOutput=
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    [[ -z "${namespace}" ]] && namespace='apigee' && logMessage -t 'info' "The default namespace ${namespace} will be used."
    ##### OPERATOR ######
    ## Dry run
    helm upgrade operator apigee-operator/ \
        --install \
        --create-namespace \
        --namespace "${namespace}" \
        --atomic \
        -f "$overridesFileName" \
        --dry-run \
        --debug | tee -a "${ABS_LOGS_FILE}"

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade operator apigee-operator/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    ## Actual installation
    #### Apigee operator
    helm upgrade operator apigee-operator/ \
        --install \
        --create-namespace \
        --namespace "${namespace}" \
        --atomic \
        -f "$overridesFileName" \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade operator apigee-operator/ --namespace ${namespace}]"
        return 1
    fi

    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "20"  "Waiting on the operator component to be provisioned..."    
        checks=0
        helmOutput=$(helm get metadata operator -n "${namespace}" -o json | jq -r ".status")

        compareTwoStrings "$helmOutput" "deployed"
        [[ "$?" != "0" ]] && checks='1'

        ## triple check for readiness for apigee controller manager
        kubectlOutput=$(kubectl -n "${namespace}" get deploy apigee-controller-manager -o json)
        [[ "$?" != "0" ]] && checks='1'

        # jq -r ".status.availableReplicas" <<< $kubectlOutput
        compareTwoStrings "$(jq -r ".status.availableReplicas" <<< $kubectlOutput)" "1"
        [[ "$?" != "0" ]] && checks='1'
        # jq -r ".status.readyReplicas" <<< $kubectlOutput
        compareTwoStrings "$(jq -r ".status.readyReplicas" <<< $kubectlOutput)" "1"
        [[ "$?" != "0" ]] && checks='1'
        #
        helm ls -n "${namespace}" | tee -a "${ABS_LOGS_FILE}"
        kubectl get deploy apigee-controller-manager -n "${namespace}" | tee -a "${ABS_LOGS_FILE}"
    done
    ## post loop check
    # compareTwoStrings "0" "$checks"
    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi
    
    return 0
}

helmUpgradeDatastore(){
    # Subfunction to install apigee-datastore
    # $1 = OVERRIDES_FILE_NAME.
    local overridesFileName="$1"
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    [[ -z "${namespace}" ]] && namespace='apigee' && logMessage -t 'info' "The default namespace ${namespace} will be used."

    # Set location
    cd "$APIGEE_HELM_CHARTS_ABSOLUTE"

    ##### DATASTORE ######
    helm upgrade datastore apigee-datastore/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f "${overridesFileName}" \
        --dry-run \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade datastore apigee-datastore/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    ## install apigee datastore
    helm upgrade datastore apigee-datastore/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f "${overridesFileName}" \
        --timeout 5m \
        --debug | tee -a "${ABS_LOGS_FILE}" 

    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade operator datastore-datastore/ --namespace ${namespace}]"
        return 1
    fi

    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "60" "Waiting on the datastore component to be provisioned..."        
        checks=0
        #
        kubectlOutput=$(kubectl -n "${namespace}" get apigeedatastore default -o json)
        [[ "$?" != "0" ]] && checks='1'
        compareTwoStrings "$(jq -r ".status.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'

        logMessage -t 'info' "The datastore component is in a '$(jq -r ".status.state" <<<$kubectlOutput)' state."

        kubectl -n "${namespace}" get apigeedatastore default | tee -a "${ABS_LOGS_FILE}"
        kubectl -n "${namespace}" get pods -l app=apigee-cassandra | tee -a "${ABS_LOGS_FILE}"
    done

    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi

    return 0
}


helmUpgradeTelemetry(){
    # Subfunction to install apigee-telemetry
    # $1 = OVERRIDES_FILE_NAME.
    local overridesFileName=$1
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    [[ -z "${namespace}" ]] && namespace='apigee' && logMessage -t 'info' "The default namespace ${namespace} will be used."

    helm upgrade telemetry apigee-telemetry/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f "$overridesFileName" \
        --dry-run \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade telemetry apigee-telemetry/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    helm upgrade telemetry apigee-telemetry/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f "$overridesFileName" \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade telemetry apigee-telemetry/ --namespace ${namespace}]"
        return 1
    fi

    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "10"  "Waiting on the telemetry component to be provisioned..."
        checks=0

        kubectlOutput=$(kubectl -n ${namespace} get apigeetelemetry apigee-telemetry -o json)
        [[ "$?" != "0" ]] && checks='1'

        compareTwoStrings "$(jq -r ".status.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'

        kubectl -n ${namespace} get apigeetelemetry apigee-telemetry | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'
        
        kubectl get pods -n ${namespace} -l "app in (collector, apigee-logger)" | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'
    done

    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi

    return 0
}


helmUpgradeRedis(){
    # Subfunction to install apigee-redis
    # $1 = OVERRIDES_FILE_NAME.
    # $2 = namespace
    local overridesFileName="$1"
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    [[ -z "${namespace}" ]] && namespace='apigee' && logMessage -t 'info' "The default namespace ${namespace} will be used."

    helm upgrade redis apigee-redis/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f $overridesFileName \
        --dry-run \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade redis apigee-redis/ --namespace ${namespace} --dry-run]"
        return 1
    fi
    
    helm upgrade redis apigee-redis/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f $overridesFileName \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade redis apigee-redis/ --namespace ${namespace}]"
        return 1
    fi

    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "10" "Waiting on the redis component to be provisioned..."
        checks=0
        kubectlOutput=$(kubectl -n "${namespace}" get apigeeredis default -o json)
        [[ "$?" != "0" ]] && checks='1'

        compareTwoStrings "$(jq -r ".status.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'

        kubectl -n "${namespace}" get apigeeredis default | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'

        kubectl get pods -n "${namespace}" -l app=apigee-redis | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'
    done

    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi
    
    return 0
}


helmUpgradeIngressManager(){
    # Subfunction to install apigee-redis
    # $1 = OVERRIDES_FILE_NAME.
    local overridesFileName=$1
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    [[ -z "${namespace}" ]] && namespace='apigee' && logMessage -t 'info' "The default namespace ${namespace} will be used."
    
    # Set location
    cd "$APIGEE_HELM_CHARTS_ABSOLUTE"

    helm upgrade ingress-manager apigee-ingress-manager/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f $overridesFileName \
        --dry-run \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade ingress-manager apigee-ingress-manager/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    helm upgrade ingress-manager apigee-ingress-manager/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f $overridesFileName \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade ingress-manager apigee-ingress-manager/ --namespace ${namespace}]"
        return 1
    fi

    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "10" "Waiting on the redis component to be provisioned..."
        checks=0        
        kubectlOutput=$(kubectl -n ${namespace} get deployment apigee-ingressgateway-manager -o json)
        [[ "$?" != "0" ]] && checks='1'
        compareTwoStrings "$(jq -r ".status.readyReplicas" <<<$kubectlOutput)" "$(jq -r ".status.replicas" <<<$kubectlOutput)"
        [[ "$?" != "0" ]] && checks='1'

        kubectl -n ${namespace} get deployment apigee-ingressgateway-manager | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'

        kubectl get pods -n ${namespace} -l app=apigee-ingressgateway-manager | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'    
    done

    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi

    return 0
}

helmUpgradeOrg(){
    # Subfunction to install apigee-redis
    # $1 = OVERRIDES_FILE_NAME.
    # $2 = NAMESPACE
    # $3 = org name
    local overridesFileName=$1
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    local orgName="$3"
    local ingressName="$4"
    local aux=".items[0].status.components.ingressGateways[\"apigee-ingressgateway-${ingressName}\"].state"
    [[ -z "${namespace}" ]] && namespace='apigee' && logMessage -t 'info' "The default namespace ${namespace} will be used."

    # Set location
    cd "$APIGEE_HELM_CHARTS_ABSOLUTE"

    helm upgrade "${orgName}" apigee-org/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f $overridesFileName \
        --dry-run \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade ${orgName} apigee-org/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    helm upgrade "${orgName}" apigee-org/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        -f $overridesFileName \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade ${orgName} apigee-org/ --namespace ${namespace}]"
        return 1
    fi
    
    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "60" "Waiting on the org component to be provisioned..."
        checks=0     
        kubectlOutput=$(kubectl -n ${namespace} get apigeeorg -o json)
        [[ "$?" != "0" ]] && checks='1' 

        logMessage -t 'debug' "kubectl -n ${namespace} get apigeeorg \n ${kubectlOutput}"
        #
        compareTwoStrings "$(jq -r ".items[0].status.components.connectAgent.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'
        #
        compareTwoStrings "$(jq -r "$aux" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'
        #
        compareTwoStrings "$(jq -r ".items[0].status.components.mart.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'
        #
        compareTwoStrings "$(jq -r ".items[0].status.components.udca.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'
        #
        compareTwoStrings "$(jq -r ".items[0].status.components.watcher.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'

        kubectl -n ${namespace} get apigeeorg | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'

        kubectl get pods -n ${namespace} -l 'app in (apigee-udca, apigee-watcher, apigee-mart, apigee-synchronizer, apigee-connect-agent)' | tee -a "${ABS_LOGS_FILE}"
        [[ "$?" != "0" ]] && checks='1'

        kubectl get secrets -n ${namespace} | grep -e "ax-salt" \
         -e "apigee-connect-agent" -e "data-encryption" \
         -e "encryption-keys" -e "apigee-mart" \
         -e "apigee-udca" -e "apigee-watcher"
        [[ "$?" != "0" ]] && checks='1'
    done

    # logMessage -t 'info' "kubectl -n ${namespace} get apigeeorg \n ${kubectlOutput}"

    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi
    
    return 0
}

helmUpgradeEnv(){
    # Subfunction to install apigee-redis
    # $1 = OVERRIDES_FILE_NAME.
    # $2 = namespace
    # $3 = env name
    local overridesFileName="$1"
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    local envName="$3"

    [[ -z "${namespace}" ]] && namespace='apigee' && logMessage -t 'info' "The default namespace ${namespace} will be used."

    helm upgrade ${envName} apigee-env/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        --set "env=${envName}" \
        -f "$overridesFileName" \
        --dry-run \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade ${envName} apigee-env/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    helm upgrade "${envName}" apigee-env/ \
        --install \
        --namespace "${namespace}" \
        --atomic \
        --set "env=${envName}" \
        -f "$overridesFileName" \
        --debug | tee -a "${ABS_LOGS_FILE}"
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade ${envName} apigee-env/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "30" "Waiting on the env '${envName}' component to be provisioned"
        checks=0  
        kubectlOutput=$(kubectl -n ${namespace} get apigeeenv -o json)
        [[ "$?" != "0" ]] && checks='1'

        compareTwoStrings "$(jq -r ".items[] | select (.spec.name == \"$envName\") | .status.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'

        kubectl -n ${namespace} get apigeeenv | tee -a "${ABS_LOGS_FILE}" 
    done

    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi

    return 0
}

helmUpgradeEnvGroup(){
    # Subfunction to install apigee-redis
    # $1 = OVERRIDES_FILE_NAME.
    # $2 = namespace
    # $3 = env group name 
    local overridesFileName="$1"
    local kubectlOutput=
    local checks=
    local maxWaitTime=600
    local start_time=
    local namespace="$2"
    local envGroupName="$3"
    local aux=". | select (.items[].metadata.labels.envGroupId == "$envGroupName")"

    # Set location
    cd "$APIGEE_HELM_CHARTS_ABSOLUTE"

    helm upgrade $envGroupName apigee-virtualhost/ \
        --install \
        --namespace ${namespace} \
        --atomic \
        --set envgroup=$envGroupName \
        -f $overridesFileName \
        --dry-run \
        --debug 
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade $envGroupName apigee-virtualhost/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    helm upgrade $envGroupName apigee-virtualhost/ \
        --install \
        --namespace ${namespace} \
        --atomic \
        --set envgroup=$envGroupName \
        -f $overridesFileName \
        --debug
    if [[ "${PIPESTATUS[0]}" != "0" ]]; then
        logMessage -t 'err' "[helm upgrade $envGroupName apigee-virtualhost/ --namespace ${namespace} --dry-run]"
        return 1
    fi

    ## waiting for the resource to get ready
    start_time=$(date +%s)
    checks=1
    while [ $(($(date +%s) - $start_time)) -le "$maxWaitTime" ] && [[ "$checks" == "1" ]]; do
        TransitionEffect "30" "Waiting on the env group '$envGroupName' apigee-virtualhost component to be provisioned..."
        checks=0  
        kubectlOutput=$(kubectl -n ${namespace} get ar -o json)
        [[ "$?" != "0" ]] && checks='1'

        compareTwoStrings "$(jq -r ".items[] | select (.metadata.labels.envGroupId == \"$envGroupName\") | .status.state" <<<$kubectlOutput)" "running"
        [[ "$?" != "0" ]] && checks='1'
        kubectl -n ${namespace} get arc | tee -a "${ABS_LOGS_FILE}"
        kubectl -n ${namespace} get ar | tee -a "${ABS_LOGS_FILE}"   
    done

    if [[ "$checks" != "0" ]]; then
        logMessage -t 'err' "loop failure."
        return 1
    fi

    return 0  
}
