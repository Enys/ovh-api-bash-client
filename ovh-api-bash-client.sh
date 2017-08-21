#!/bin/bash

# DEFAULT CONFIG
OVH_CONSUMER_KEY=""
OVH_APP_KEY=""
OVH_APP_SECRET=""

CONSUMER_KEY_FILE=".ovhConsumerKey"
OVH_APPLICATION_FILE=".ovhApplication"
LIBS="libs"

TARGETS=(CA EU)

declare -A API_URLS
API_URLS[CA]="https://ca.api.ovh.com/1.0"
API_URLS[EU]="https://api.ovh.com/1.0"

declare -A API_CREATE_APP_URLS
API_CREATE_APP_URLS[CA]="https://ca.api.ovh.com/createApp/"
API_CREATE_APP_URLS[EU]="https://api.ovh.com/createApp/"

BASE_PATH="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROFILES_PATH="${BASE_PATH}/profile"

HELP_CMD="$0"

# THESE VARS WILL BE USED LATER
METHOD="GET"
URL="/me"
TARGET="EU"
TIME=""
SIGDATA=""
POST_DATA=""
PROFILE=""

isTargetValid()
{
    VALID=0
    for i in ${TARGETS[@]}
    do
        if [ $i == "$TARGET" ]
        then
            VALID=1
            break
        fi
    done

    if [ $VALID -eq 0 ]
    then
        echo "Error: $TARGET is not a valid target, accepted values are: ${TARGETS[@]}"
        echo
        help
        exit 1
    fi
}

createApp()
{

    echo "For which OVH API do you want to create a new API Application? ($( echo ${TARGETS[@]} | sed 's/\s/|/g' ))"
    while [ -z "$NEXT" ]
    do
        read NEXT
    done
    TARGET=$( echo $NEXT | tr [:lower:] [:upper:] )
    isTargetValid

    echo
    echo -e "In order to create an API Application, please visit the link below:\n${API_CREATE_APP_URLS[$TARGET]}"
    echo
    echo "Once your application is created, we will configure this script for this application"
    echo -n "Enter the Application Key: "
    read OVH_APP_KEY
    echo -n "Enter the Application Secret: "
    read OVH_APP_SECRET
    echo "OK!"
    echo "These informations will be stored in the following file: $CURRENT_PATH/${OVH_APPLICATION_FILE}_${TARGET}"
    echo -e "${OVH_APP_KEY}\n${OVH_APP_SECRET}" > $CURRENT_PATH/${OVH_APPLICATION_FILE}_${TARGET}

    echo
    echo "Do you also need to create a consumer key? (y/n)"
    read NEXT
    if [ -n "$NEXT" ] && [ $( echo $NEXT | tr [:upper:] [:lower:] ) = y ]
    then
        createConsumerKey
    else
        echo -e "OK, no consumer key created for now.\nYou will be able to initalize the consumer key later calling :\n${HELP_CMD} --init"
    fi
}

createConsumerKey()
{

    METHOD="POST"
    URL="/auth/credential"

    # ensure an OVH App key is set
    initApplication
    hasOvhAppKey || exit 1

    # all grants if no post data defined
    if [ -z "${POST_DATA}" ]; then
      POST_DATA='{ "accessRules": [ { "method": "GET", "path": "/*"}, { "method": "PUT", "path": "/*"}, { "method": "POST", "path": "/*"}, { "method": "DELETE", "path": "/*"} ] }'
    fi
    ANSWER=$(requestNoAuth)

    getJSONFieldString "$ANSWER" 'consumerKey' > $CURRENT_PATH/${CONSUMER_KEY_FILE}_${TARGET}
    echo -e "In order to validate the generated consumerKey, visit the validation url at:\n$(getJSONFieldString "$ANSWER" 'validationUrl')"
}

initConsumerKey()
{
    cat $CURRENT_PATH/${CONSUMER_KEY_FILE}_${TARGET} &> /dev/null
    if [ $? -eq 0 ]
    then
        OVH_CONSUMER_KEY="$(cat $CURRENT_PATH/${CONSUMER_KEY_FILE}_${TARGET})"
    fi
}

initApplication()
{
    cat $CURRENT_PATH/${OVH_APPLICATION_FILE}_${TARGET} &> /dev/null
    if [ $? -eq 0 ]
    then
        OVH_APP_KEY=$(sed -n 1p $CURRENT_PATH/${OVH_APPLICATION_FILE}_${TARGET})
        OVH_APP_SECRET=$(sed -n 2p $CURRENT_PATH/${OVH_APPLICATION_FILE}_${TARGET})
    fi
}

updateTime()
{
    TIME=$(date '+%s')
}

updateSignData()
{
    SIGDATA="$OVH_APP_SECRET+$OVH_CONSUMER_KEY+$1+${API_URLS[$TARGET]}$2+$3+$TIME"
    SIG='$1$'$(echo -n $SIGDATA | sha - | cut -d' ' -f1)
}

help()
{
    echo
    echo "Help: possible arguments are:"
    echo "  --url <url>             : the API URL to call, for example /domains (default is /me)"
    echo "  --method <method>       : the HTTP method to use, for example POST (default is GET)"
    echo "  --data <JSON data>      : the data body to send with the request"
    echo "  --target <$( echo ${TARGETS[@]} | sed 's/\s/|/g' )>        : the target API (default is EU)"
    echo "  --init                  : to initialize the consumer key"
    echo "  --initApp               : to initialize the API application"
    echo "  --list-profile          : list available profiles in profile/ directory"
    echo "  --profile <value>"
    echo "            * default : from script directory"
    echo "            * <dir>   : from profile/<dir> directory"
    echo
}

parseArguments()
{
    # an action launched out of this function
    INIT_KEY_ACTION=

    while [ $# -gt 0 ]
    do
        case $1 in
        --data)
            shift
            POST_DATA=$1
            ;;
        --init)
            INIT_KEY_ACTION="ConsumerKey"
            ;;
        --initApp)
            INIT_KEY_ACTION="AppKey"
            ;;
        --method)
            shift
            METHOD=$1
            ;;
        --url)
            shift
            URL=$1
            ;;
        --target)
            shift
            TARGET=$1
            isTargetValid
            ;;
        --profile)
            shift
            PROFILE=$1
            ;;
        --list-profile)
            listProfile
            exit 0
            ;;
        --help|-h)
            help
            exit 0
            ;;
        *)
            echo "Unknow parameter $1"
            help
            exit 0
            ;;
        esac
        shift
    done

}

requestNoAuth()
{
    updateTime
    curl -s -X $METHOD --header 'Content-Type:application/json;charset=utf-8' --header "X-Ovh-Application:$OVH_APP_KEY" --header "X-Ovh-Timestamp:$TIME" --data "$POST_DATA" ${API_URLS[$TARGET]}$URL
}

request()
{
    updateTime
    updateSignData "$METHOD" "$URL" "$POST_DATA"
    RESPONSE=$(curl -s -w "\n%{http_code}\n" -X $METHOD --header 'Content-Type:application/json;charset=utf-8' --header "X-Ovh-Application:$OVH_APP_KEY" --header "X-Ovh-Timestamp:$TIME" --header "X-Ovh-Signature:$SIG" --header "X-Ovh-Consumer:$OVH_CONSUMER_KEY" --data "$POST_DATA" ${API_URLS[$TARGET]}$URL)
    RESPONSE_STATUS=$(echo "$RESPONSE" | sed -n '$p')
    RESPONSE_CONTENT=$(echo "$RESPONSE" | sed '$d')
    echo "$RESPONSE_STATUS $RESPONSE_CONTENT"
}

getJSONFieldString()
{
    JSON="$1"
    FIELD="$2"
    RESULT=$(echo $JSON | $BASE_PATH/$LIBS/JSON.sh | grep "\[\"$FIELD\"\]" | sed -r "s/\[\"$FIELD\"\]\s+(.*)/\1/")
    echo ${RESULT:1:${#RESULT}-2}
}

# set CURRENT_PATH with profile name
# usage : initProfile |set|get] profile_name
#  set : create the profile if missing
#  get : raise an error if no profile with that name
initProfile()
{
  local createProfile=$1
  local profile=$2

  if [ ! -d "${PROFILES_PATH}" ]
  then
    mkdir "${PROFILES_PATH}" || exit 1
  fi

  # if profile is not set, or with value 'default'
  if [[ -z "${profile}" ]] || [[ "${profile}" == "default" ]]
  then
    # configuration stored in the script path
    CURRENT_PATH="${BASE_PATH}"
  else
    # ensure profile directory exists
    if [ ! -d "${PROFILES_PATH}/${profile}" ]
    then
     case ${createProfile} in
        get)
          echo "${PROFILES_PATH}/${profile} should exists"
          listProfile
          exit 1
          ;;
        set)
          mkdir "${PROFILES_PATH}/${profile}" || exit 1
          ;;
      esac
    fi
    # override default configuration location
    CURRENT_PATH="$( cd "${PROFILES_PATH}/${profile}" && pwd )"
  fi

  if [ -n "${profile}" ] 
  then
    HELP_CMD="${HELP_CMD} --profile ${profile}"
  fi

}

listProfile()
{
  local dir=
  echo "Available profiles : "
  echo "- default"

  if [ -d "${PROFILES_PATH}" ]
  then
        # only list directory
    for dir in $(cd ${PROFILES_PATH} && ls -d */ 2>/dev/null)
    do
      # display directory name without slash
      echo "- ${dir%%/}"
    done
  fi
}

# ensure OVH App Key an App Secret are defined
hasOvhAppKey()
{
    if [ -z "$OVH_APP_KEY" ] && [ -z "$OVH_APP_SECRET" ]
    then
        echo -e "No application is defined for target $TARGET, please call to initialize it:\n${HELP_CMD} --initApp"
        return 1
    fi
    return 0
}

main()
{

    parseArguments "$@"

    local profileAction="get"

    if [ -n "${INIT_KEY_ACTION}" ]; then
        profileAction="set"
    fi

    initProfile ${profileAction} ${PROFILE}

    # user want to add An API Key
    case ${INIT_KEY_ACTION} in
      AppKey) createApp;;
      ConsumerKey) createConsumerKey;;
    esac
    ## exit after initializing any API Keys
    [ -n "${INIT_KEY_ACTION}" ] && exit 0

    initApplication
    initConsumerKey

    if hasOvhAppKey
    then
      if [ -z "$OVH_CONSUMER_KEY" ]; then
        echo -e "No consumer key for target $TARGET, please call to initialize it:\n${HELP_CMD} --init"
      else
        request $METHOD $URL
      fi
    fi
}


main "$@"
