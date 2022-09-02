FROM nginx:1.23.1

RUN apt update
RUN apt install -y curl xz-utils less git

RUN curl -sOL https://ziglang.org/builds/zig-linux-x86_64-0.10.0-dev.3842+36f4f32fa.tar.xz && \
  tar Jxf zig-linux-x86_64-0.10.0-dev.3842+36f4f32fa.tar.xz

RUN git clone http://github.com/jdmichaud/zpz && \
  cd zpz && \
  git submodule init && \
  git submodule update && \
  ../zig-linux-x86_64-0.10.0-dev.3842+36f4f32fa/zig build wasm -Drelease-fast=true

RUN cp /zpz/web/* /usr/share/nginx/html && \
  cp /zpz/zig-out/lib/zpz6128.wasm /usr/share/nginx/html
