FROM nginxinc/nginx-unprivileged:alpine

COPY k8s/index.html /usr/share/nginx/html/index.html