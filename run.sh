#!/usr/bin/env bash

if [ ! -n "$WERCKER_ACCS_DEPLOY_ACC_REST_URL" ]; then
    error 'Please specify  Oracle Application Container Cloud REST url. (e.g.: https://apaas.europe.oraclecloud.com/paas/service/apaas/api/v1.1/apps)'
    error '(Locate Oracle Application Container Cloud in the My Services console, click Details, and look at the REST Endpoint value.)'
    exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN"]; then
    error 'Please specify OPC identity domain'
    exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_OCI_USER" ]; then
    error 'Please specify OCI user'
    exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_OCI_PASSWORD" ]; then
    error 'Please specify OCI password'
    exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_APPLICATION_NAME" ]; then
  error 'Please specify application name (application container cloud service instance name)'
  exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_APPLICATION_TYPE" ]; then
  error 'Please specify application type (java|node|php)'
  exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_SUBSCRIPTION_TYPE" ]; then
  error 'Please specify your subscription type (Hourly|Monthly)'
  exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_SUBSCRIPTION_TYPE" ]; then
  error 'Please specify your subscription type (Hourly|Monthly)'
  exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_STORAGE_AUTH_URL" ]; then
  error 'Please specify Object Storage Authorization URL'
  exit 1
fi

if [ ! -n "$WERCKER_ACCS_DEPLOY_STORAGE_REST_URL" ]; then
  error 'Please specify Object Storage REST URL'
  exit 1
fi



export ARCHIVE_LOCAL=target/$WERCKER_ACCS_DEPLOY_FILE

if [ ! -e "$ARCHIVE_LOCAL" ]; then
  echo "Error: file not found '${ARCHIVE_LOCAL}'"
  exit -1
fi

echo "File found '${ARCHIVE_LOCAL}'"

getStorageTokenAndURLSet() {
    echo '[info] Fetching Storage Auth Token and URL.'

    shopt -s extglob
    while IFS=':' read key value; do
          value=${value##+([[:space:]])}; value=${value%%+([[:space:]])}
          case "$key" in
            X-Auth-Token) export STORAGE_AUTH_TOKEN="$value"
                  ;;
            X-Storage-Url) export STORAGE_URL="$value"
                  ;;
          esac
    done< <(curl -sI -X GET -H "X-Storage-User: Storage-${WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN}:${WERCKER_ACCS_DEPLOY_OIC_USER}" -H "X-Storage-Pass: ${WERCKER_ORACLE_ACCS_DEPLOY_OPC_PASSWORD}" "https://${WERCKER_ACCS_DEPLOY_STORAGE_AUTH_URL}")

    if [ ! -n "$STORAGE_AUTH_TOKEN" ]; then
        error 'Unable to fetch storage auth token, please check your OPC Username and password.'
        exit 1
    fi

    if [ ! -n "$STORAGE_URL" ]; then
        error 'Unable to fetch storage url, please check your OPC Username and password.'
        exit 1
    fi    
}

createStorageContainer() {
    getStorageTokenAndURLSet

    echo '[info] Creating Storage Container.'
    curl -i -X PUT \
        -H "X-Auth-Token: $STORAGE_AUTH_TOKEN" \
        "$STORAGE_URL/$WERCKER_ACCS_DEPLOY_APPLICATION_NAME"
}

uploadACCSArchive() {
    getStorageTokenAndURLSet

    echo '[info] Uploading application to storage'
    curl -i -X PUT \
        -H "X-Auth-Token: $STORAGE_AUTH_TOKEN" \
        -T "$ARCHIVE_LOCAL"
        "$STORAGE_URL/$WERCKER_ACCS_DEPLOY_APPLICATION_NAME/$WERCKER_ACCS_DEPLOY_FILE"

}

# Create Container
createStorageContainer

# Put Archive in Storage Container
uploadACCSArchive

# See if application exists
export httpCode=$(curl -i -X GET  \
  -u "${WERCKER_ACCS_DEPLOY_OCI_USER}:${WERCKER_ACCS_DEPLOY_OCI_PASSWORD}" \
  -H "X-ID-TENANT-NAME:${WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN}" \
  -H "Content-Type: multipart/form-data" \
  -sL -w "%{http_code}" \
  "${WERCKER_ACCS_DEPLOY_ACC_REST_URL}/${WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN}/${WERCKER_ACCS_DEPLOY_APPLICATION_NAME}" \
  -o /dev/null)

# If application exists...
if [ "$httpCode" == 200 ]
then
  # Update application
  echo '[info] Updating application...'
  curl -i -X PUT  \
    -u "${WERCKER_ACCS_DEPLOY_OCI_USER}:${WERCKER_ACCS_DEPLOY_OCI_PASSWORD}" \
    -H "X-ID-TENANT-NAME:${WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN}" \
    -H "Content-Type: multipart/form-data" \
    -F "archiveURL=${WERCKER_ACCS_DEPLOY_APPLICATION_NAME}/${WERCKER_ACCS_DEPLOY_FILE}" \
    -F "deployment=@deployment.json" \
    "${WERCKER_ACCS_DEPLOY_ACC_REST_URL}/${WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN}/${WERCKER_ACCS_DEPLOY_APPLICATION_NAME}"
else
  # Create application and deploy
  echo '[info] Creating application...'
  curl -i -X POST  \
    -u "${WERCKER_ACCS_DEPLOY_OCI_USER}:${WERCKER_ACCS_DEPLOY_OCI_PASSWORD}" \
    -H "X-ID-TENANT-NAME:${WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN}" \
    -H "Content-Type: multipart/form-data" \
    -F "name=${WERCKER_ACCS_DEPLOY_APPLICATION_NAME}" \
    -F "runtime=${WERCKER_ACCS_DEPLOY_APPLICATION_TYPE}" \
    -F "subscription=${WERCKER_ACCS_DEPLOY_SUBSCRIPTION_TYPE}" \
    -F "archiveURL=${WERCKER_ACCS_DEPLOY_APPLICATION_NAME}/${WERCKER_ACCS_DEPLOY_FILE}" \
    -F "deployment=@deployment.json" \
    "${WERCKER_ACCS_DEPLOY_REST_URL}/${WERCKER_ACCS_DEPLOY_IDENTITY_DOMAIN}"
fi

echo '[info] Deployment complete'
