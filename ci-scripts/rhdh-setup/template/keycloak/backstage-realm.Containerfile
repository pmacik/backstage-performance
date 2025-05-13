FROM registry.access.redhat.com/ubi9/ubi

RUN mkdir -p /realm-data
RUN mkdir -p /mnt/realm-data

COPY backstage-realm.entrypoint.sh /entrypoint.sh

WORKDIR /realm-data

COPY backstage-realm.*.json.tar.gz .

CMD ["/entrypoint.sh"]

