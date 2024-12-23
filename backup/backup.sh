#!/usr/bin/env bash
set -e

# Timestamp
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Local backup file path
LOCAL_BACKUP_FILE="/tmp/appflowy_${DATE}.sql"

# Dump the Postgres DB
pg_dump "${APPFLOWY_BACKEND__DATABASE__URL}" > "${LOCAL_BACKUP_FILE}"

# Upload to S3 (e.g., s3://BUCKET_NAME/backups/appflowy_YYYY-MM-DD_HH-MM-SS.sql)
aws s3 cp "${LOCAL_BACKUP_FILE}" "s3://${S3_BUCKET_NAME}/backups/appflowy_${DATE}.sql"

# Remove local file after upload (optional to save container space)
rm -f "${LOCAL_BACKUP_FILE}"

# -----------------------------------------------------------
# Delete S3 objects older than 7 days
# We'll parse the output of 'aws s3 ls' and compare timestamps.
# -----------------------------------------------------------
OLDER_THAN_SECS=$(date -d "-7 days" +%s)

# List all objects under s3://BUCKET/backups/
aws s3 ls "s3://${S3_BUCKET_NAME}/backups/" --recursive | while read -r line; do
  # Example line format:
  # 2023-05-10 01:23:45     12345 backups/appflowy_2023-05-10_01-23-45.sql
  #
  # Pull out date/time fields (1st & 2nd columns) and the object key (4th column).
  OBJECT_DATE=$(echo "$line" | awk '{print $1}')
  OBJECT_TIME=$(echo "$line" | awk '{print $2}')
  OBJECT_KEY=$(echo "$line" | awk '{print $4}')

  # Convert the date/time to epoch
  OBJECT_DATETIME="${OBJECT_DATE} ${OBJECT_TIME}"
  OBJECT_SECS=$(date -d "$OBJECT_DATETIME" +%s || true)

  # If the object's date is older than OLDER_THAN_SECS, delete it
  if [ "$OBJECT_SECS" -lt "$OLDER_THAN_SECS" ]; then
    echo "Deleting old backup: s3://${S3_BUCKET_NAME}/${OBJECT_KEY}"
    aws s3 rm "s3://${S3_BUCKET_NAME}/${OBJECT_KEY}"
  fi
done
