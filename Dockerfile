FROM nginx:1.23.1

RUN apt update
RUN apt install -y curl xz-utils less git

RUN curl -sOL https://ziglang.org/download/0.12.0/zig-linux-x86_64-0.12.0.tar.xz && \
  tar Jxf zig-linux-x86_64-0.12.0.tar.xz

RUN git clone http://github.com/jdmichaud/zpz && \
  cd zpz && \
  git submodule init && \
  git submodule update && \
  ../zig-linux-x86_64-0.12.0/zig build wasm -Doptimize=ReleaseSmall

RUN cp -r /zpz/web/* /usr/share/nginx/html && \
  cp --remove-destination /zpz/zig-out/bin/zpz6128.wasm /usr/share/nginx/html/
