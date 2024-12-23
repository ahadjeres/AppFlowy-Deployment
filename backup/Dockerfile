# backup/Dockerfile

FROM alpine:3.18

# Install pg_dump (postgresql-client) + bash + curl + unzip (needed by AWS CLI)
RUN apk add --no-cache postgresql-client bash curl unzip

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip" \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/*

# Copy our scripts
COPY backup-cron.sh /backup-cron.sh
COPY backup.sh /backup.sh
RUN chmod +x /backup.sh /backup-cron.sh

# Run cron in foreground
CMD ["/backup-cron.sh"]
