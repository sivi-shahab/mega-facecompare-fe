# ==========================================
# Stage Build Application
# ==========================================
FROM imageregistry.bankmegadev.com:5000/nodejs/node:12.22.12-alpine AS builder

# Proxy
ENV http_proxy=http://10.190.21.24:3128
ENV https_proxy=http://10.190.21.24:3128
ENV no_proxy=localhost,127.0.0.1,.bankmega.com
ENV HTTP_PROXY=http://10.190.21.24:3128
ENV HTTPS_PROXY=http://10.190.21.24:3128
ENV NO_PROXY=localhost,127.0.0.1,.bankmega.com

WORKDIR /usr/src/app

# Copy dependency files
COPY ui/package*.json .

# Install package
RUN npm install 

# Copy source code
COPY ui/ .

# Build application
RUN npm run build:prod

# ==========================================
# Stage Final App
# ==========================================
FROM imageregistry.bankmegadev.com:5000/nginxinc/nginx-unprivileged:1.21.1 AS base

# Default non-rahasia; override lewat env / ConfigMap.
ENV ADMIN_UPSTREAM=compreface-admin-service:8080 
ENV API_UPSTREAM=compreface-api-service:8080 
ENV CORE_UPSTREAM=compreface-core-service:3000 
ENV NGINX_RESOLVER="" 
ENV NGINX_RESOLVER_VALID=10s 
ENV NGINX_UPSTREAM_AUTO_FQDN=true 
ENV CLIENT_MAX_BODY_SIZE=10M 
ENV PROXY_READ_TIMEOUT=60000ms 
ENV PROXY_CONNECT_TIMEOUT=10000ms

ARG VERSION=dev
ARG REVISION=unknown

LABEL org.opencontainers.image.title="compreface-fe" 
LABEL org.opencontainers.image.version="${VERSION}" 
LABEL org.opencontainers.image.revision="${REVISION}" 
LABEL org.opencontainers.image.source="https://github.com/exadel-inc/CompreFace" 
LABEL org.opencontainers.image.licenses="Apache-2.0" 
LABEL org.opencontainers.image.vendor="mega (repackaged from Exadel CompreFace)"

# remove default configuration
RUN rm -f /etc/nginx/conf.d/default.conf

# Copy nginx configuration
COPY --chown=appuser:appuser ui/nginx/mime.types /etc/nginx/mime.types
COPY --chown=appuser:appuser docker/nginx.conf /etc/nginx/nginx.conf
COPY --chown=appuser:appuser docker/nginx.conf.template /etc/nginx/templates/nginx.conf.template

# Copy build result
COPY --chown=appuser:appuser --chmod=0755 docker/docker-entrypoint-fe.sh /usr/local/bin/docker-entrypoint-fe.sh
COPY --chown=appuser:appuser --from=builder /usr/src/app/dist/compreface /usr/share/nginx/html
COPY LICENSE NOTICE /usr/share/licenses/compreface/

RUN chown -R appuser:appuser /etc/nginx/conf.d && chmod -R g+w /etc/nginx/conf.d

# Cleanup Proxy
ENV http_proxy=
ENV https_proxy=
ENV no_proxy=localhost,127.0.0.1,.bankmega.com
ENV HTTP_PROXY=
ENV HTTPS_PROXY=
ENV NO_PROXY=localhost,127.0.0.1,.bankmega.com

# Define user
USER appuser

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-fe.sh"]
CMD ["nginx", "-g", "daemon off;"]
