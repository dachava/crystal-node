FROM nginxinc/nginx-unprivileged:alpine

COPY k8s/crystal-app/index.html /usr/share/nginx/html/index.html