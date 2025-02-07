#!/bin/bash




# echo "RESULT OF THE MENU OPTIONS '${MENU_RESULT}'."

# whiptailMenu(){
#     TERMINAL_WIDTH=$(tput cols)
#     TERMINAL_HEIGHT=$(tput lines)
#     MENU_FRACTION_VALUE=2
#     MENU_HEIGHT=$((${TERMINAL_HEIGHT}/${MENU_FRACTION_VALUE}))
#     MENU_WIDTH=$((${TERMINAL_WIDTH}/${MENU_FRACTION_VALUE}))
#     MENU_LIST_HEIGHT=$((${MENU_HEIGHT}/2))
    
#     # Calculate menu dimensions
#     # Minimum width and height
#     MIN_WIDTH=40
#     MIN_HEIGHT=10

#     local menuTitle=
#     local menuMessage=
#     local menuOptions=

#     local reqVars=('menuTitle'
#     'menuMessage'
#     'menuOptions')

#     local menuResult=

#     while :; do
#         case $1 in
#         --title)
#             if [[ -z "$2" ]]; then
#                 echo "[ERROR][${FUNCNAME[*]}] '--title' flag needs non-empty value.">&2
#                 return 1
#             fi
#             menuTitle="$2"
#             shift
#         ;;
#         --message)
#             if [[ -z "$2" ]]; then
#                 echo "[ERROR][${FUNCNAME[*]}] '--message' flag needs non-empty value.">&2
#                 return 1
#             fi
#             menuMessage="$2"
#             shift
#         ;;
#         --options)
#             while [[ ! -z "$2" && "$2" != -* ]]; do
#                 menuOptions+=("$2")
#                 shift 
#             done
#             # if [[ -z "$2" ]]; then
#             #     echo "[ERROR][${FUNCNAME[*]}] '--options' flag needs non-empty value."
#             #     return 1
#             # fi
#         ;;
#         *)
#             break
#         ;;
#         esac
#     shift
#     done

    

#     ## reindex/slicing
#     menuOptions=("${menuOptions[@]:1}")
#     ## verification
#     for reqvar in "${reqVars[@]}"; do
#         [[ -z "${!reqvar}" ]] && echo "[ERROR][${FUNCNAME[*]}] variable '${reqvar}' must be non-empty.">&2 && return 1
#     done

#     menuResult=$(whiptail --title "${menuTitle}" \
#     --menu "${menuMessage}" "${MENU_HEIGHT}" "${MENU_WIDTH}" $((${MENU_HEIGHT}-4)) \
#     "${menuOptions[@]}" \
#     --clear \
#     --ok-button "Select" \
#     --cancel-button "Return" \
#     3>&1 1>&2 2>&3)

#     [[ "$?" != '0' ]] && \
#     return 1
#     echo "$menuResult"
#     return "$?"
# }

whiptailMenu() {
    # Get terminal dimensions
    TERMINAL_WIDTH=$(tput cols)
    TERMINAL_HEIGHT=$(tput lines)
    
    # Minimum dimensions for the menu
    MIN_WIDTH=40
    MIN_HEIGHT=10

    # Variables for the menu
    local menuTitle=
    local menuMessage=
    local menuOptions=()

    # Required variables
    local reqVars=('menuTitle' 'menuMessage' 'menuOptions')
    local menuResult=

    # Parse input arguments
    while :; do
        case $1 in
        --title)
            if [[ -z "$2" ]]; then
                echo "[ERROR][${FUNCNAME[*]}] '--title' flag needs a non-empty value." >&2
                return 1
            fi
            menuTitle="$2"
            shift
        ;;
        --message)
            if [[ -z "$2" ]]; then
                echo "[ERROR][${FUNCNAME[*]}] '--message' flag needs a non-empty value." >&2
                return 1
            fi
            menuMessage="$2"
            shift
        ;;
        --options)
            while [[ ! -z "$2" && "$2" != -* ]]; do
                menuOptions+=("$2")
                shift
            done
        ;;
        *)
            break
        ;;
        esac
        shift
    done

    # Reindex/slicing (if needed)
    menuOptions=("${menuOptions[@]}")

    # Verify required variables
    for reqvar in "${reqVars[@]}"; do
        [[ -z "${!reqvar}" ]] && echo "[ERROR][${FUNCNAME[*]}] Variable '${reqvar}' must be non-empty." >&2 && return 1
    done

    # Dynamic menu dimensions
    local totalOptions=${#menuOptions[@]}  # Count total options
    local maxVisibleOptions=$((TERMINAL_HEIGHT - 7)) # Space for options with padding
    if [[ $totalOptions -gt $maxVisibleOptions ]]; then
        MENU_HEIGHT=$((maxVisibleOptions))  # Restrict height to fit within the terminal
    else
        MENU_HEIGHT=$((totalOptions + 7))  # Add padding
    fi
    MENU_WIDTH=$((TERMINAL_WIDTH / 2))
    MENU_LIST_HEIGHT=$((MENU_HEIGHT - 6))  # List height excludes menu header/footer

    # Respect minimum dimensions
    if [[ "$MENU_WIDTH" -lt "$MIN_WIDTH" ]]; then
        MENU_WIDTH=$MIN_WIDTH
    fi
    if [[ "$MENU_HEIGHT" -lt "$MIN_HEIGHT" ]]; then
        MENU_HEIGHT=$MIN_HEIGHT
        MENU_LIST_HEIGHT=$((MIN_HEIGHT - 4))
    fi

    # Ensure menu dimensions fit terminal
    if [[ "$MENU_HEIGHT" -gt "$TERMINAL_HEIGHT" ]]; then
        MENU_HEIGHT=$((TERMINAL_HEIGHT - 2))
        MENU_LIST_HEIGHT=$((MENU_HEIGHT - 6))
    fi

    if [[ "$MENU_WIDTH" -gt "$TERMINAL_WIDTH" ]]; then
        MENU_WIDTH=$((TERMINAL_WIDTH - 2))
    fi

    # Display the menu
    menuResult=$(whiptail --title "${menuTitle}" \
        --menu "${menuMessage}" "${MENU_HEIGHT}" "${MENU_WIDTH}" "${MENU_LIST_HEIGHT}" \
        "${menuOptions[@]}" \
        --clear \
        --ok-button "Select" \
        --cancel-button "Return" \
        3>&1 1>&2 2>&3)

    # Handle cancellation
    [[ "$?" != '0' ]] && return 1

    echo "$menuResult"
    return 0
}



whiptailInputBox() {
    # Get terminal dimensions
    TERMINAL_WIDTH=$(tput cols)
    TERMINAL_HEIGHT=$(tput lines)

    # Minimum dimensions for the input box
    MIN_WIDTH=40
    MIN_HEIGHT=10

    # Variables for the input box
    local inputTitle=""
    local inputMessage=""
    local defaultValue=""

    # Required variables
    local reqVars=('inputTitle' 'inputMessage')
    local inputResult=""

    # Parse input arguments
    while :; do
        case $1 in
        --title)
            if [[ -z "$2" ]]; then
                echo "[ERROR][${FUNCNAME[*]}] '--title' flag needs a non-empty value." >&2
                return 1
            fi
            inputTitle="$2"
            shift
        ;;
        --message)
            if [[ -z "$2" ]]; then
                echo "[ERROR][${FUNCNAME[*]}] '--message' flag needs a non-empty value." >&2
                return 1
            fi
            inputMessage="$2"
            shift
        ;;
        --default)
            # if [[ -z "$2" ]]; then
            #     echo "[ERROR][${FUNCNAME[*]}] '--default' flag needs a non-empty value." >&2
            #     return 1
            # fi
            defaultValue="$2"
            shift
        ;;
        *)
            break
        ;;
        esac
        shift
    done

    # Verify required variables
    for reqvar in "${reqVars[@]}"; do
        [[ -z "${!reqvar}" ]] && echo "[ERROR][${FUNCNAME[*]}] Variable '${reqvar}' must be non-empty." >&2 && return 1
    done

    # Dynamic input box dimensions
    INPUT_HEIGHT=$((TERMINAL_HEIGHT / 2)) # Input box height as half of terminal height
    INPUT_WIDTH=$((TERMINAL_WIDTH / 2))   # Input box width as half of terminal width

    # Respect minimum dimensions
    if [[ "$INPUT_WIDTH" -lt "$MIN_WIDTH" ]]; then
        INPUT_WIDTH=$MIN_WIDTH
    fi
    if [[ "$INPUT_HEIGHT" -lt "$MIN_HEIGHT" ]]; then
        INPUT_HEIGHT=$MIN_HEIGHT
    fi

    # Ensure input box dimensions fit terminal
    if [[ "$INPUT_HEIGHT" -gt "$TERMINAL_HEIGHT" ]]; then
        INPUT_HEIGHT=$((TERMINAL_HEIGHT - 2))
    fi
    if [[ "$INPUT_WIDTH" -gt "$TERMINAL_WIDTH" ]]; then
        INPUT_WIDTH=$((TERMINAL_WIDTH - 2))
    fi

    # Display the input box
    inputResult=$(whiptail --title "${inputTitle}" \
        --inputbox "${inputMessage}" "${INPUT_HEIGHT}" "${INPUT_WIDTH}" "${defaultValue}" \
        --clear 3>&1 1>&2 2>&3)

    # Handle cancellation
    [[ "$?" != '0' ]] && return 1

    # Return the input
    echo "$inputResult"
    return 0
}



