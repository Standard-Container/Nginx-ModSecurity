FROM alpine:3.20 AS builder

# 安装编译所需的依赖
RUN apk add --no-cache autoconf automake libtool build-base git yajl-dev geoip-dev libmaxminddb-dev lmdb-dev lua5.4-dev curl-dev libxml2-dev pcre2-dev linux-headers openssl-dev gd-dev

# 复制源码到 Docker 镜像
COPY ../modules/ssdeep /tmp/ssdeep
COPY ../modules/ModSecurity /tmp/ModSecurity
COPY ../modules/nginx /tmp/nginx
COPY ../modules/ModSecurity-nginx /tmp/ModSecurity-nginx

# 编译 ModSecurity 依赖
WORKDIR /tmp/ssdeep
RUN ./bootstrap && ./configure CFLAGS="-O3" && make -j$(nproc) && make install

# 编译 ModSecurity
WORKDIR /tmp/ModSecurity
RUN ./build.sh && ./configure --with-pcre2 --with-lmdb CFLAGS="-O3" && make -j$(nproc) && make install

# 编译 Nginx
WORKDIR /tmp/nginx
RUN ./auto/configure \
    --with-http_ssl_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_realip_module \
    --with-http_addition_module \
    --with-http_image_filter_module \
    --with-http_geoip_module \
    --with-http_sub_module \
    --with-http_dav_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_auth_request_module \
    --with-http_slice_module \
    --with-http_stub_status_module \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_ssl_module \
    --with-stream_realip_module \
    --with-stream_geoip_module \
    --with-stream_ssl_preread_module \
    --add-module=/tmp/ModSecurity-nginx \
    --with-cc-opt='-O3'
RUN make -j$(nproc) && make install

# 创建最终的镜像
FROM alpine:3.20

# 设置必要的运行时依赖
RUN apk add --no-cache pcre2 gd libcurl libxml2 lmdb lua5.4-libs libmaxminddb-libs libstdc++ libgcc yajl geoip

# 从 builder 镜像复制编译好的 Nginx、ModSecurity、ssdeep
COPY --from=builder /usr/local/nginx /usr/local/nginx
COPY --from=builder /usr/local/modsecurity /usr/local/modsecurity
COPY --from=builder /usr/local/lib/libfuzzy.so.2 /usr/local/lib/libfuzzy.so.2

# 设置 PATH，这样我们就可以直接运行 nginx 命令
ENV PATH="/usr/local/nginx/sbin:${PATH}"

# 暴露端口
EXPOSE 80 443

# 当容器启动时运行 Nginx
CMD ["nginx", "-g", "daemon off;"]
