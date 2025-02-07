#!/bin/bash


#######################################################
##### Main Script for Apigee Hybrid Installation  #####
#######################################################

# SOURCE
## filename for the values of the env variables, stored and updated
FUNCTIONS_DIR="commons"
## env files under $FUNCTIONS_DIR
ENV_VALUES="values.env"
JSON_VARIABLES_ENV='json_variables.env'
OVERRIDES_TEMPLATES_ENV='overrides_templates.env'
YAML_TEMPLATES_ENV='yaml_templates.env'
## commons functions files under $FUNCTIONS_DIR
FUNCTIONS_FILE="functions.sh"
MESSAGE_FUNCTIONS_FILE="message_functions.sh"
COLOR_FUNCTIONS_FILE="color_functions.sh"
CACHE_FUNCTIONS_FILE="caching_functions.sh"
FILEPROC_FUNCTIONS_FILE="fileproc_functions.sh"
HELM_UPGRADE_FUNCTIONS_FILE="helm_upgrade_functions.sh"
LOOPCURL_FUNCTIONS_FILE="loopcurl.sh"
BASIC_FUNCTIONS_FILE='basic_functions.sh'
CLUSTER_FUNCTIONS_FILE='cluster_functions.sh'
DEPENDENCY_FUNCTIONS_FILE='dep_check.sh'
ERASE_FUNCTIONS_FILE='erase_functions.sh'
WHIPTAIL_FUNCTIONS_FILE='whiptail_functions.sh'
VAR_MENU_FUNCTIONS_FILE='var_menus.sh'

#
FILE_LIST=("$ENV_VALUES" 
"$JSON_VARIABLES_ENV"
"$OVERRIDES_TEMPLATES_ENV"
"$YAML_TEMPLATES_ENV"
"$MESSAGE_FUNCTIONS_FILE"
"$COLOR_FUNCTIONS_FILE" 
"$CACHE_FUNCTIONS_FILE" 
"$FILEPROC_FUNCTIONS_FILE"
"$HELM_UPGRADE_FUNCTIONS_FILE" 
"$LOOPCURL_FUNCTIONS_FILE"
"$BASIC_FUNCTIONS_FILE"
"$CLUSTER_FUNCTIONS_FILE"
"$DEPENDENCY_FUNCTIONS_FILE"
"$FUNCTIONS_FILE"
"$ERASE_FUNCTIONS_FILE"
"$WHIPTAIL_FUNCTIONS_FILE"
"$VAR_MENU_FUNCTIONS_FILE"
)
#

## Store script location
declare -g MAIN_SCRIPT_LOCATION=${PWD}
declare -g LOGS_FILE="logs.d/installer"
declare -g "DEBUG_MODE"="false"

# create logs file
declare -g LOGS_FILE="${LOGS_FILE}_$(date +'%Y-%m-%d_%H-%M-%S').log"
mkdir -p "$(dirname "${LOGS_FILE}")"
touch "${LOGS_FILE}"
ABS_LOGS_FILE="${MAIN_SCRIPT_LOCATION}/${LOGS_FILE}"

## Source functions
# echo "[$0] Sourcing files located in ${FUNCTIONS_DIR}:" >&2
for file in "${FILE_LIST[@]}"; do 
    # echo "[$0] Sourcing ${file} ..." >&2
    source "${PWD}/${FUNCTIONS_DIR}/${file}"
    if [[ "$?" != "0" ]]; then return 1; fi 
done
# more env vars to declare
declare -g RUNTIME_FLAGS_FILE_ABSOLUTE="${MAIN_SCRIPT_LOCATION}/${RUNTIME_FLAGS_FILE}"
declare -g CACHED_VALUES_FILE_ABSOLUTE="${MAIN_SCRIPT_LOCATION}/${CACHED_VALUES_FILE}"

# init log
echo "### Apigee Hybrid Installer Script ###
### ### ### ### ### ### ### ### ### ### ###" | tee -a "${LOGS_FILE}"
## Main script initialization.
initialization
## Options
mainFlagsHandling "$@" 

## Default Menu Type
declare -g MENU_TYPE='WHIPTAIL'
## case handling
case "$INSTALLATION_TYPE" in
            AUTO)
                ## DEPENDENCY CHECKS
                dependenciesCheck
                [[ "$?" != 0 ]] && exit 1 
                if [[ "${MENU_TYPE^^}" == 'WHIPTAIL' ]]; then
                    wahm
                elif [[ "${MENU_TYPE^^}" == 'BASH' ]]; then
                    automaticHybridMenu 
                fi
                ;;
            MANUAL)       
                ## DEPENDENCY CHECKS
                dependenciesCheck
                [[ "$?" != 0 ]] &&  exit 1
                if [[ "${MENU_TYPE^^}" == 'WHIPTAIL' ]]; then
                    wmhm
                elif [[ "${MENU_TYPE^^}" == 'BASH' ]]; then
                    manualHybridMenu 
                fi
                ;;
            NOMENU)
                dependenciesCheck
                [[ "$?" != 0 ]] &&  exit 1
                automaticInstallater
                ;;
            ERASE)
                ## DEPENDENCY CHECKS
                dependenciesCheck
                [[ "$?" != 0 ]] &&  exit 1 
                mainDeleteSequence "${ERASE_LIST[@]}"
                ;;
            HELP)
                echo "$MAIN_HELP_MESSAGE"
                ;;
esac

exit "$?"
