FROM metacubex/mihomo:latest AS mihomo

FROM alpine:3.22
RUN apk add --no-cache bash curl jq coreutils grep gawk
COPY --from=mihomo /mihomo /usr/local/bin/mihomo
COPY docker/entrypoint.sh /app/entrypoint.sh
ENTRYPOINT ["bash", "/app/entrypoint.sh"]
